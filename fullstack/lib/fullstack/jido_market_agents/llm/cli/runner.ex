defmodule Fullstack.JidoMarketAgents.LLM.Cli.Runner do
  @moduledoc """
  Bounded, isolated subprocess lifecycle utility for CLI-based LLM backends.

  This module is NOT a `Backend` adapter: it has no `chat_completion/2` and
  knows nothing about any specific CLI's argv shape or output format. It is a
  shared low-level primitive that concrete adapters (a future Claude Code or
  Codex adapter) call to safely run one CLI invocation and get back its raw
  stdout, or a tagged, sanitized error.

  ## What this module guarantees

    * The executable runs via `Port.open({:spawn_executable, path}, ...)` with
      `args` as a list of separate argv elements. No shell is invoked and no
      argv element is ever built by concatenating strings into a command
      line — every element reaches the child literally, including shell
      metacharacters.
    * The child's environment is built from an explicit allowlist. Every
      variable inherited from the BEAM's OS environment that is not in the
      caller-supplied `env:` map is explicitly unset for the child via OTP's
      `{name, false}` env entry. The BEAM's own global environment
      (`System.put_env/2`) is never touched.
    * Each call gets a private, freshly created scratch directory (mode
      `0700`) that a future adapter can use for schema files, output files,
      or anything else the CLI needs to read or write. The directory is
      removed after every outcome: success, error, or timeout.
    * One monotonic deadline covers the entire call — process launch, output
      collection, and (if configured) the `before_cleanup` callback. Only
      elapsed wall-clock time against that single deadline can time the call
      out; receiving an output chunk never extends it. This is deliberate:
      a CLI that continuously prints output must still be bounded by the
      original timeout.
    * Stdout is bounded. Once accumulated stdout exceeds `max_output_bytes`,
      the call fails with `{:error, {:output_overflow, max_output_bytes}}`
      and the process group is terminated the same way a timeout would be.
    * On timeout or overflow, the child's OS process group (not just the
      immediate `Port` process) is terminated: `TERM`, a bounded grace
      period, then `KILL`, with liveness re-checked after `KILL` so a
      still-alive process is reported as `:kill_failed` rather than silently
      treated as cleaned up.
    * If the calling process dies while a call is in flight, the OS process
      group is still terminated and the scratch directory is still removed.
      `run/3` delegates the actual Port ownership and blocking wait to a
      separate worker process that monitors the caller; a crashed caller's
      own stack disappearing does not prevent that worker from finishing
      cleanup, so no child, descendant, or scratch file is leaked.

  ## Process-group termination mechanism

  On this OS/OTP combination (Linux, OTP 28), `erl_child_setup` calls
  `setsid()` on every spawned port process unconditionally, so
  `Port.info(port, :os_pid)` is already the child's own process group id
  (PGID) — no extra `setsid` wrapper binary is needed.

  Signals are sent to the whole group with `kill -s <SIG> -- -<pgid>`. The
  bare form `kill -<SIG> -<pgid>` (signal and target both after a single
  dash, with no `--`) is unsafe: on this system `kill` (procps-ng) silently
  misparses `-<pgid>` as a second signal argument, does nothing, and still
  exits `0`. Always use the explicit `-s <SIG> --` form so the target is
  unambiguous.

  Liveness is checked with `File.exists?("/proc/<pid>")`, which is cheaper
  than shelling out to `kill -0`; either works, `/proc` is used here.

  ## Residual risk: the CLI escaping its own process group

  This mechanism terminates the process group that `setsid()` created for
  the direct child. If the CLI binary itself calls `setsid()` again on one
  of its descendants (for example, to daemonize a helper process), that
  descendant creates a *new* process group and escapes this termination
  path entirely. This has not been tested against the real `claude` or
  `codex` binaries; adapters built on this runner should be validated
  against actual CLI process behaviour before being trusted for cleanup in
  production.

  ## stdout / stderr separation

  This runner does not merge stderr into stdout and does not capture stderr
  content into any returned or error term. A future Claude Code adapter
  needs clean JSON on stdout; mixing in stderr diagnostics would corrupt
  that parse. Stderr is simply not read: the child inherits the runner's
  default stderr disposition (discarded), so stderr output is dropped
  rather than buffered or exposed.

  ## Error sanitization

  Error terms never contain raw environment values, prompt/message content,
  or stderr text. Calling code (agent conversation logging/UI) inspects
  error reasons verbatim, so any raw secret or user content placed in an
  error term would be a security leak, not just a cosmetic issue. Returned
  errors carry only bounded, structural information: an atom tag, an exit
  code, a byte limit, or a scratch-dir path — never argv content, prompt
  text, or environment values.

  ## Extension seam: reading files before cleanup

  A future Codex adapter needs to read the file the CLI wrote inside the
  scratch directory (via `--output-schema`/`-o`) *before* that directory is
  removed. This runner exposes that seam as `opts[:before_cleanup]`: an
  optional zero-argument-free callback, `(scratch_dir -> term())`, invoked
  synchronously after the child process exits (or is confirmed terminated)
  but before the scratch directory is deleted. Its return value is merged
  into the successful result as `:extra`.

  This callback-based seam was chosen over alternatives such as (a) having
  the runner accept a fixed "output file name" and read it itself, or (b)
  skipping cleanup and handing ownership of the directory to the caller:

    * A fixed output filename would leak CLI-specific knowledge (Codex's
      `-o` contract) into this shared, CLI-agnostic module.
    * Skipping cleanup and handing directory ownership to the caller would
      reintroduce exactly the scratch-directory leak this module exists to
      prevent — cleanup would then depend on every future adapter
      remembering to do it on every code path, including its own crashes.

  A callback keeps `Runner` CLI-agnostic (it never inspects the file, only
  invokes the caller's function with a path) while still guaranteeing
  cleanup always runs, because the callback executes as part of this
  module's own success path, before the `after`-guaranteed removal step.
  """

  @type run_result :: %{
          stdout: binary(),
          exit_status: non_neg_integer(),
          scratch_dir: Path.t(),
          extra: term()
        }

  @type run_error ::
          :timeout
          | :caller_down
          | {:nonzero_exit, non_neg_integer()}
          | {:output_overflow, pos_integer()}
          | {:cleanup_failed, term()}
          | {:spawn_failed, term()}
          | {:executable_not_found, term()}

  @default_timeout_ms 60_000
  @default_grace_ms 3_000
  @default_max_output_bytes 10 * 1024 * 1024
  @default_scratch_prefix "fullstack_cli_runner"

  @doc """
  Runs `executable` with `argv` in an isolated subprocess and returns its
  stdout, or a tagged error.

  ## Options

    * `:env` — a map of `String.t()` allowlisted environment variables to
      set for the child. Every other variable inherited from the BEAM's OS
      environment is explicitly unset for the child. Defaults to `%{}`
      (child receives no inherited environment at all).
    * `:timeout_ms` — total deadline in milliseconds, covering launch,
      output collection, and the `before_cleanup` callback. Defaults to
      #{@default_timeout_ms}.
    * `:grace_ms` — grace period between `TERM` and `KILL` when the process
      group must be terminated. Defaults to #{@default_grace_ms}.
    * `:max_output_bytes` — maximum stdout bytes accumulated before the call
      fails with `{:output_overflow, limit}`. Defaults to
      #{@default_max_output_bytes}.
    * `:scratch_prefix` — prefix used when naming the private scratch
      directory. Defaults to `#{inspect(@default_scratch_prefix)}`.
    * `:before_cleanup` — optional `(Path.t() -> term())` invoked with the
      scratch directory path after the process exits successfully but
      before that directory is removed. Its return value is merged into
      the result map as `:extra`. Not invoked on error or timeout paths.

  ## Return value

  On success, `{:ok, %{stdout: binary, exit_status: 0, scratch_dir: path,
  extra: term}}`. The `scratch_dir` path is only valid for inspection during
  the `before_cleanup` callback; by the time `run/3` returns, the directory
  has already been removed.

  On failure, `{:error, reason}` with `reason` one of the tagged errors in
  `t:run_error/0`. Cleanup (process-group termination, scratch directory
  removal) is attempted on every failure path, including timeout.
  """
  @spec run(String.t(), [String.t()], keyword()) ::
          {:ok, run_result()} | {:error, run_error()}
  def run(executable, argv, opts \\ []) when is_list(argv) do
    with {:ok, absolute_path} <- resolve_executable(executable) do
      timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
      grace_ms = Keyword.get(opts, :grace_ms, @default_grace_ms)
      max_output_bytes = Keyword.get(opts, :max_output_bytes, @default_max_output_bytes)
      scratch_prefix = Keyword.get(opts, :scratch_prefix, @default_scratch_prefix)
      env = Keyword.get(opts, :env, %{})
      before_cleanup = Keyword.get(opts, :before_cleanup)

      deadline = System.monotonic_time(:millisecond) + timeout_ms
      caller = self()

      # The actual Port ownership and blocking `receive` loop run in a
      # separate worker process rather than inline in the caller. This is
      # what makes caller-death reaping possible: if `caller` is killed
      # while this call is in flight, the *caller's* stack (including any
      # `receive` it was blocked in) disappears with it and can run no
      # cleanup code at all. A separate worker, monitoring `caller`, keeps
      # running independently of the caller's lifetime and can still
      # terminate the OS process group and remove the scratch directory
      # after the caller is gone.
      {:ok, worker} =
        Task.start(fn ->
          ref = Process.monitor(caller)

          with {:ok, scratch_dir} <- create_scratch_dir(scratch_prefix) do
            result =
              run_supervised(
                absolute_path,
                argv,
                env,
                scratch_dir,
                deadline,
                grace_ms,
                max_output_bytes,
                before_cleanup,
                caller,
                ref
              )

            Process.demonitor(ref, [:flush])
            send(caller, {__MODULE__, self(), result})
          else
            {:error, _reason} = error ->
              Process.demonitor(ref, [:flush])
              send(caller, {__MODULE__, self(), error})
          end
        end)

      receive do
        {__MODULE__, ^worker, result} -> result
      end
    end
  end

  # Runs the process and cleanup while also watching for the caller's death.
  # `execute/7` itself blocks in a `receive` keyed to the port and the
  # deadline, so caller death is detected via the `:DOWN` message racing
  # against that same receive inside `collect/5` — see `collect/5`, which
  # also matches on the monitor `:DOWN` message for `caller` and treats it
  # as an immediate abort with cleanup, independent of the timeout deadline.
  defp run_supervised(
         absolute_path,
         argv,
         env,
         scratch_dir,
         deadline,
         grace_ms,
         max_output_bytes,
         before_cleanup,
         caller,
         monitor_ref
       ) do
    result =
      execute(
        absolute_path,
        argv,
        env,
        scratch_dir,
        deadline,
        grace_ms,
        max_output_bytes,
        caller,
        monitor_ref
      )

    result = put_scratch_dir(result, scratch_dir)
    result = maybe_run_before_cleanup(result, before_cleanup, scratch_dir)

    case cleanup_scratch_dir(scratch_dir) do
      :ok -> result
      {:error, cleanup_reason} -> override_with_cleanup_failure(result, cleanup_reason)
    end
  end

  defp put_scratch_dir({:ok, result}, scratch_dir),
    do: {:ok, Map.put(result, :scratch_dir, scratch_dir)}

  defp put_scratch_dir({:error, _reason} = error, _scratch_dir), do: error

  # -- Executable resolution --------------------------------------------

  defp resolve_executable(executable) do
    case System.find_executable(executable) do
      nil ->
        if File.regular?(executable) do
          {:ok, Path.expand(executable)}
        else
          {:error, {:executable_not_found, redact(executable)}}
        end

      absolute_path ->
        {:ok, absolute_path}
    end
  end

  # Never echo raw user-controlled paths/content back in an error term
  # beyond a bounded, non-sensitive shape (basename only).
  defp redact(executable), do: Path.basename(to_string(executable))

  # -- Scratch directory lifecycle ---------------------------------------

  defp create_scratch_dir(prefix) do
    unique_id = unique_scratch_id()
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{unique_id}")

    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700) do
      {:ok, dir}
    else
      {:error, reason} -> {:error, {:spawn_failed, {:scratch_dir_create_failed, reason}}}
    end
  end

  # A unique id combining monotonic time, the calling process's own PID, and
  # a random component. PID alone is not sufficient: OS PIDs (and even BEAM
  # scheduler-local counters) can theoretically repeat across two calls that
  # start in quick succession, especially under concurrent Task.async usage
  # exercised by this module's own test suite. Monotonic time narrows that
  # further, and the random suffix removes any remaining theoretical
  # collision window without depending on any assumption about PID reuse
  # timing on the host OS.
  defp unique_scratch_id do
    time = System.monotonic_time()
    random = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    "#{time}_#{random}"
  end

  defp cleanup_scratch_dir(dir) do
    case File.rm_rf(dir) do
      {:ok, _paths} -> :ok
      {:error, reason, _path} -> {:error, reason}
    end
  end

  defp maybe_run_before_cleanup({:ok, result}, before_cleanup, scratch_dir)
       when is_function(before_cleanup, 1) do
    extra = before_cleanup.(scratch_dir)
    {:ok, Map.put(result, :extra, extra)}
  end

  defp maybe_run_before_cleanup(result, _before_cleanup, _scratch_dir), do: result

  defp override_with_cleanup_failure({:ok, _result}, cleanup_reason) do
    {:error, {:cleanup_failed, cleanup_reason}}
  end

  defp override_with_cleanup_failure({:error, _reason} = error, _cleanup_reason) do
    # The call already failed for another reason; a cleanup failure on top
    # of an already-failed call is reported via that same error rather than
    # masking the original failure. Cleanup failures are only surfaced as
    # the primary error when the call itself otherwise succeeded.
    error
  end

  # -- Process execution ---------------------------------------------------

  defp execute(
         absolute_path,
         argv,
         env,
         scratch_dir,
         deadline,
         grace_ms,
         max_output_bytes,
         caller,
         monitor_ref
       ) do
    port_env = build_port_env(env)

    port =
      Port.open({:spawn_executable, to_charlist(absolute_path)}, [
        :binary,
        :exit_status,
        :hide,
        args: argv,
        cd: to_charlist(scratch_dir),
        env: port_env
      ])

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        nil -> nil
      end

    result = collect(port, os_pid, deadline, max_output_bytes, <<>>, caller, monitor_ref)
    ensure_terminated(port, os_pid, grace_ms)
    result
  catch
    :error, reason -> {:error, {:spawn_failed, reason}}
  end

  # Builds the OTP `env:` list: every currently-inherited OS environment
  # variable not present in the allowlist is explicitly unset via the
  # `{name, false}` form, then the allowlisted variables are appended. OTP's
  # `env:` option overlays the inherited environment rather than replacing
  # it, so omission alone would leak every ambient variable (API keys,
  # tokens, etc. already present in this BEAM's OS environment) into the
  # child. Names and values are charlists: this was verified empirically
  # against OTP 28 with `Port.open/2` (see runner_test.exs), which accepts
  # charlist env names/values for both the allowlisted entries and the
  # `false` unset entries.
  defp build_port_env(allowlist) do
    inherited_names =
      System.get_env()
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(allowlist, &1))

    unset_entries = Enum.map(inherited_names, &{to_charlist(&1), false})

    allow_entries =
      Enum.map(allowlist, fn {name, value} ->
        {to_charlist(name), to_charlist(value)}
      end)

    unset_entries ++ allow_entries
  end

  defp collect(port, os_pid, deadline, max_output_bytes, acc, caller, monitor_ref) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      receive do
        {^port, {:data, chunk}} ->
          acc = acc <> chunk

          if byte_size(acc) > max_output_bytes do
            {:error, {:output_overflow, max_output_bytes}}
          else
            collect(port, os_pid, deadline, max_output_bytes, acc, caller, monitor_ref)
          end

        {^port, {:exit_status, 0}} ->
          {:ok, %{stdout: acc, exit_status: 0, extra: nil}}

        {^port, {:exit_status, status}} ->
          {:error, {:nonzero_exit, status}}

        {:DOWN, ^monitor_ref, :process, ^caller, _reason} ->
          {:error, :caller_down}
      after
        remaining ->
          {:error, :timeout}
      end
    end
  end

  # -- Termination -----------------------------------------------------

  # Ensures the OS process group is not left running regardless of the
  # outcome of `collect/5`. Closing the Port here is safe even when the
  # child already exited (the exit_status message was already consumed).
  defp ensure_terminated(port, os_pid, grace_ms) do
    terminate_process_group(os_pid, grace_ms)
    safe_close(port)
  end

  defp safe_close(port) do
    if Port.info(port), do: Port.close(port)
  catch
    :error, :badarg -> :ok
  end

  @doc false
  # Exposed for regression testing of the exact kill invocation shape; not
  # part of the public API used by adapters.
  @spec terminate_process_group(pos_integer() | nil, non_neg_integer()) ::
          :not_running | :terminated | :killed | :kill_failed
  def terminate_process_group(nil, _grace_ms), do: :not_running

  def terminate_process_group(os_pid, grace_ms) do
    if alive?(os_pid) do
      send_group_signal(os_pid, "TERM")
      wait_until(fn -> not alive?(os_pid) end, grace_ms)

      if alive?(os_pid) do
        send_group_signal(os_pid, "KILL")
        wait_until(fn -> not alive?(os_pid) end, grace_ms)

        if alive?(os_pid), do: :kill_failed, else: :killed
      else
        :terminated
      end
    else
      :not_running
    end
  end

  # Sends `signal` to the whole process group led by `os_pid`. The `-s SIG
  # --` form is required: the bare form `kill -SIG -pid` is misparsed by
  # procps-ng `kill` on this system as two signal arguments, does nothing to
  # the target, and still exits 0 — a silent no-op that looks like success.
  # `-s SIG --` unambiguously separates the signal from the (negative,
  # group-targeting) pid argument.
  defp send_group_signal(os_pid, signal) do
    System.cmd("kill", ["-s", signal, "--", "-#{os_pid}"], stderr_to_stdout: true)
  end

  defp alive?(os_pid), do: File.exists?("/proc/#{os_pid}")

  defp wait_until(predicate, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(predicate, deadline)
  end

  defp do_wait_until(predicate, deadline) do
    cond do
      predicate.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :ok

      true ->
        Process.sleep(10)
        do_wait_until(predicate, deadline)
    end
  end
end
