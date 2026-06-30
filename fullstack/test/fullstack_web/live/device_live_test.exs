defmodule FullstackWeb.DeviceLiveTest do
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.DevicesFixtures

  @create_attrs %{
    enabled: true,
    wlan_mac_address: "some wlan_mac_address",
    eth_mac_address: "some eth_mac_address"
  }
  @update_attrs %{
    enabled: false,
    wlan_mac_address: "some updated wlan_mac_address",
    eth_mac_address: "some updated eth_mac_address"
  }
  @invalid_attrs %{enabled: false, wlan_mac_address: nil, eth_mac_address: nil}

  defp create_device(%{conn: conn}) do
    device = device_fixture()
    user = Fullstack.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), device: device}
  end

  describe "Index" do
    setup [:create_device]

    test "lists all devices", %{conn: conn, device: device} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/devices")

      assert html =~ "Devices"
      assert html =~ device.wlan_mac_address
    end

    test "saves new device", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/devices")

      assert index_live |> element("a", "New Device") |> render_click() =~
               "New Device"

      assert_patch(index_live, ~p"/admin/devices/new")

      assert index_live
             |> form("#device-form", device: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#device-form", device: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/admin/devices")

      html = render(index_live)
      assert html =~ "Device created successfully"
      assert html =~ "some wlan_mac_address"
    end

    test "updates device in listing", %{conn: conn, device: device} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/devices")

      assert index_live |> element("#devices-#{device.id} a", "Edit") |> render_click() =~
               "Edit Device"

      assert_patch(index_live, ~p"/admin/devices/#{device}/edit")

      assert index_live
             |> form("#device-form", device: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#device-form", device: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/admin/devices")

      html = render(index_live)
      assert html =~ "Device updated successfully"
      assert html =~ "some updated wlan_mac_address"
    end

    test "deletes device in listing", %{conn: conn, device: device} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/devices")

      assert index_live |> element("#devices-#{device.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#devices-#{device.id}")
    end
  end

  describe "Show" do
    setup [:create_device]

    test "displays device", %{conn: conn, device: device} do
      {:ok, _show_live, html} = live(conn, ~p"/admin/devices/#{device}")

      assert html =~ "Show Device"
      assert html =~ device.wlan_mac_address
    end

    test "updates device within modal", %{conn: conn, device: device} do
      {:ok, show_live, _html} = live(conn, ~p"/admin/devices/#{device}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Device"

      assert_patch(show_live, ~p"/admin/devices/#{device}/show/edit")

      assert show_live
             |> form("#device-form", device: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#device-form", device: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/admin/devices/#{device}")

      html = render(show_live)
      assert html =~ "Device updated successfully"
      assert html =~ "some updated wlan_mac_address"
    end
  end
end
