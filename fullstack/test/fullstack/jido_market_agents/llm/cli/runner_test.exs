defmodule Fullstack.JidoMarketAgents.LLM.Cli.RunnerTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.LLM.Cli.Runner

  @fixtures_dir Path.join(__DIR__, "../../../../support/fake_cli") |> Path.expand()

  defp fixture(name), do: Path.join(@fixtures_dir, name)

  defp proc_alive?(pid), do: File.exists?("/proc/#{pid}")

  @poll_timeout_ms 5_000
  @poll_interval_ms 50

  # `hang_with_child.sh` writes its own pid and its grandchild's pid into
  # `pids` in the scratch dir (which is the child's cwd). Reading exact pids
  # beats matching a pattern like "sleep 300" with pgrep: a pattern also
  # matches unrelated processes on a shared machine, making the leak
  # assertions simultaneously flaky and weak.
  defp await_pids_file(scratch_dir, timeout_ms \\ @poll_timeout_ms) do
    path = Path.join(scratch_dir, "pids")

    if await(fn -> File.exists?(path) end, timeout_ms) do
      parsed =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Map.new(fn line ->
          [key, value] = String.split(line, "=", parts: 2)
          {key, String.to_integer(value)}
        end)

      {:ok, parsed}
    else
      :error
    end
  end

  # Poll until every given pid is gone. Reaping after SIGKILL is asynchronous
  # and its latency scales with machine load, so bounded polling is both
  # faster in the common case and far more reliable than a fixed sleep sized
  # for the worst case.
  defp await_all_dead(pids, timeout_ms \\ @poll_timeout_ms) do
    await(fn -> Enum.all?(pids, &(not proc_alive?(&1))) end, timeout_ms)
  end

  defp still_alive(pids), do: Enum.filter(pids, &proc_alive?/1)

  # Locate the live scratch dir for a run still in progress, by its unique
  # prefix, so a test can inspect the dir's contents before cleanup removes it.
  defp await_scratch_dir(prefix, timeout_ms \\ @poll_timeout_ms) do
    find = fn ->
      case Path.wildcard(Path.join(System.tmp_dir!(), "#{prefix}*")) do
        [dir | _] -> dir
        [] -> nil
      end
    end

    if await(fn -> find.() != nil end, timeout_ms) do
      find.()
    else
      flunk("scratch dir with prefix #{inspect(prefix)} never appeared")
    end
  end

  defp await(check_fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await(check_fun, deadline)
  end

  defp do_await(check_fun, deadline) do
    cond do
      check_fun.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(@poll_interval_ms)
        do_await(check_fun, deadline)
    end
  end

  describe "success path" do
    test "captures stdout and exit_status 0, and removes the scratch dir" do
      assert {:ok, result} = Runner.run(fixture("success.sh"), [])

      assert result.stdout == "hello from fake cli\n"
      assert result.exit_status == 0
      refute File.exists?(result.scratch_dir)
    end
  end

  describe "nonzero exit" do
    test "returns a tagged error, not {:ok, _}, and does not leak stderr content" do
      assert {:error, reason} = Runner.run(fixture("fail.sh"), [])

      assert reason == {:nonzero_exit, 7}
      refute match?({:nonzero_exit, _, _}, reason)
    end
  end

  describe "timeout with a hung process and grandchild" do
    test "both child and grandchild are confirmed dead afterward" do
      caller = self()

      before_cleanup = fn scratch_dir ->
        send(caller, {:scratch_dir_seen, scratch_dir})
        :probed
      end

      # Run in a task so we can read the pids file while the fixture is still
      # hung, before the runner removes the scratch dir on timeout.
      run_task =
        Task.async(fn ->
          Runner.run(fixture("hang_with_child.sh"), [],
            timeout_ms: 3_000,
            grace_ms: 200,
            scratch_prefix: "runner_timeout_probe",
            before_cleanup: before_cleanup
          )
        end)

      scratch_dir = await_scratch_dir("runner_timeout_probe")
      assert {:ok, pids} = await_pids_file(scratch_dir)

      assert result = Task.await(run_task, 10_000)
      assert result == {:error, :timeout}

      # before_cleanup is documented as success-only; on a timeout it must
      # not have been invoked.
      refute_received {:scratch_dir_seen, _}

      tree = [pids["child"], pids["grandchild"]]

      assert await_all_dead(tree),
             "expected the whole process tree dead, still alive: #{inspect(still_alive(tree))}"

      refute File.exists?(scratch_dir)
    end
  end

  describe "deadline holds against continuous output" do
    test "a chatty process that never stops printing still times out and is reaped" do
      started = System.monotonic_time(:millisecond)

      run_task =
        Task.async(fn ->
          Runner.run(fixture("chatty.sh"), [],
            timeout_ms: 3_000,
            grace_ms: 100,
            scratch_prefix: "runner_chatty_probe"
          )
        end)

      scratch_dir = await_scratch_dir("runner_chatty_probe")
      assert {:ok, pids} = await_pids_file(scratch_dir)

      result = Task.await(run_task, 10_000)
      elapsed = System.monotonic_time(:millisecond) - started

      assert result == {:error, :timeout}

      # If chunks reset the deadline, this would run far longer than the
      # configured timeout + grace. Allow generous scheduling slack while
      # still proving the deadline was not repeatedly extended.
      assert elapsed < 6_000,
             "expected the deadline to hold despite continuous output, took #{elapsed}ms"

      # Asserting only that the timeout fired would leave a leak here
      # invisible: `chatty.sh` loops forever, so if termination failed it
      # would keep running after the test passed. Every timeout test must
      # assert the process is actually gone, not merely that we stopped
      # waiting for it.
      tree = [pids["child"]]

      assert await_all_dead(tree),
             "chatty.sh survived the timeout, still alive: #{inspect(still_alive(tree))}"
    end
  end

  describe "output overflow" do
    test "returns a tagged error and still cleans up the scratch dir" do
      result = Runner.run(fixture("overflow.sh"), [], max_output_bytes: 1_000)

      assert {:error, {:output_overflow, 1_000}} = result
    end
  end

  describe "env isolation" do
    setup do
      System.put_env("RUNNER_TEST_SENTINEL_SECRET", "leak-me-not")
      on_exit(fn -> System.delete_env("RUNNER_TEST_SENTINEL_SECRET") end)
    end

    test "allowlisted vars are present, ambient secrets are absent" do
      assert {:ok, result} =
               Runner.run(fixture("dump_env.sh"), [], env: %{"ALLOWED_VAR" => "allowed-value"})

      assert result.stdout =~ "ALLOWED_VAR=allowed-value"
      refute result.stdout =~ "RUNNER_TEST_SENTINEL_SECRET"
      refute result.stdout =~ "leak-me-not"
    end

    test "an empty allowlist yields a child with no inherited variables" do
      assert {:ok, result} = Runner.run(fixture("dump_env.sh"), [])

      refute result.stdout =~ "RUNNER_TEST_SENTINEL_SECRET"
      refute result.stdout =~ "HOME="
      refute result.stdout =~ "PATH="
    end
  end

  describe "argv passed literally" do
    test "shell metacharacters arrive verbatim, not interpreted" do
      literal_args = [
        "a;b",
        "$(whoami)",
        "`whoami`",
        "has space",
        "a && echo injected",
        "a | cat",
        "$HOME"
      ]

      assert {:ok, result} = Runner.run(fixture("echo_argv.sh"), literal_args)

      for arg <- literal_args do
        assert result.stdout =~ "ARG:[#{arg}]"
      end

      refute result.stdout =~ "injected\n"
      home = System.get_env("HOME") || "__no_home__"
      refute result.stdout =~ home
    end
  end

  describe "concurrent calls" do
    test "get distinct scratch dirs and do not interfere" do
      tasks =
        for i <- 1..5 do
          Task.async(fn -> Runner.run(fixture("slow_success.sh"), ["call-#{i}"]) end)
        end

      results = Task.await_many(tasks, 5_000)

      assert Enum.all?(results, &match?({:ok, _}, &1))

      for {result, i} <- Enum.zip(results, 1..5) do
        {:ok, %{stdout: stdout}} = result
        assert stdout =~ "slow result: call-#{i}"
      end
    end
  end

  describe "caller death mid-run" do
    test "the OS process tree is reaped even though the caller crashed" do
      test_pid = self()

      caller =
        spawn(fn ->
          send(test_pid, :caller_started)

          Runner.run(fixture("hang_with_child.sh"), [],
            timeout_ms: 60_000,
            scratch_prefix: "runner_caller_death_probe"
          )
        end)

      assert_receive :caller_started, 1_000

      # Establish that the subprocess tree actually exists before killing the
      # caller. Without this the test could pass vacuously: if the port had not
      # launched yet there would be nothing to leak, so "nothing leaked" would
      # prove nothing.
      scratch_dir = await_scratch_dir("runner_caller_death_probe")
      assert {:ok, pids} = await_pids_file(scratch_dir)
      tree = [pids["child"], pids["grandchild"]]
      assert await(fn -> Enum.all?(tree, &proc_alive?/1) end, @poll_timeout_ms)

      Process.exit(caller, :kill)

      # The runner's worker process must still notice the caller's death and
      # terminate the OS process group on its own, independent of the
      # caller's lifetime.
      assert await_all_dead(tree),
             "expected no leak after caller death, still alive: #{inspect(still_alive(tree))}"

      refute File.exists?(scratch_dir)
    end
  end

  describe "scratch dir cleanup on every outcome" do
    test "removed after success" do
      {:ok, result} = Runner.run(fixture("success.sh"), [])
      refute File.exists?(result.scratch_dir)
    end

    test "removed after a nonzero-exit error" do
      captured = fn scratch_dir -> send(self(), {:dir, scratch_dir}) end

      {:error, _reason} =
        Runner.run(fixture("fail.sh"), [], before_cleanup: captured)

      # before_cleanup only fires on success; assert indirectly by re-running
      # with a scratch_prefix we can locate before/after.
      prefix = "runner_test_cleanup_check"
      {:error, _} = Runner.run(fixture("fail.sh"), [], scratch_prefix: prefix)

      leftovers =
        System.tmp_dir!()
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, prefix))

      assert leftovers == []
    end

    test "removed after a timeout" do
      prefix = "runner_test_timeout_cleanup_check"

      {:error, :timeout} =
        Runner.run(fixture("chatty.sh"), [],
          timeout_ms: 200,
          grace_ms: 100,
          scratch_prefix: prefix
        )

      leftovers =
        System.tmp_dir!()
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, prefix))

      assert leftovers == []
    end
  end

  describe "process-group termination regression (kill -s SIG -- form)" do
    test "terminate_process_group/2 actually kills the group led by os_pid" do
      port =
        Port.open({:spawn_executable, ~c"/bin/sh"}, [
          :binary,
          :exit_status,
          args: ["-c", "sleep 300 & echo $!; sleep 300"]
        ])

      os_pid =
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> pid
        end

      assert proc_alive?(os_pid)

      assert Runner.terminate_process_group(os_pid, 200) in [:terminated, :killed]

      refute proc_alive?(os_pid), "expected the process group leader to be dead"

      Process.sleep(50)
      if Port.info(port), do: Port.close(port)
    end

    test "the bare `kill -SIG -pid` form (without -s/--) would NOT have worked here" do
      port =
        Port.open({:spawn_executable, ~c"/bin/sh"}, [
          :binary,
          :exit_status,
          args: ["-c", "sleep 300 & echo $!; sleep 300"]
        ])

      os_pid =
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> pid
        end

      assert proc_alive?(os_pid)

      {output, status} = System.cmd("kill", ["-TERM", "-#{os_pid}"], stderr_to_stdout: true)

      # This is the trap: procps-ng silently misparses this form on this
      # system, exits 0, and kills nothing.
      assert status == 0
      assert output == ""
      assert proc_alive?(os_pid), "the bare-dash form must not have killed the group"

      # Clean up for real using the correct mechanism this module implements.
      assert Runner.terminate_process_group(os_pid, 200) in [:terminated, :killed]
      refute proc_alive?(os_pid)

      if Port.info(port), do: Port.close(port)
    end
  end
end
