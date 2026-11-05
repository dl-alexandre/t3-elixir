defmodule T3.CLITest do
  use ExUnit.Case, async: true
  alias T3.CLI

  setup do
    dir = Path.join(System.tmp_dir!(), "t3-cli-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    exe = Path.join(dir, "fixture")

    File.write!(exe, """
    #!/bin/sh
    case "$1" in
      --help) printf 'SUBCOMMANDS\n  project    Manage projects.\n  service    Manage service.\n';;
      --version) printf 't3 fixture';;
      fail) printf 'failure details' >&2; exit 7;;
      wait) exec /bin/sleep 10;;
      stdin) exec /bin/cat;;
      flood) printf '012345678901234567890123456789';;
      env) printf '%s' "$T3_TEST_VALUE";;
      home) printf '%s' "${HOME+x}";;
      *) printf '%s\n' "$@";;
    esac
    """)

    File.chmod!(exe, 0o700)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, cli: CLI.new(executable: exe, cwd: dir)}
  end

  test "literal argv, version, help and installed command discovery", %{cli: cli} do
    assert {:ok, %{output: "t3 fixture"}} = CLI.version(cli)
    assert {:ok, [%{name: "project"}, %{name: "service"}]} = CLI.commands(cli)
    assert {:ok, %{output: output}} = CLI.run(cli, ["$(touch sentinel)", "a b", "`id`", "--flag"])
    assert output == "$(touch sentinel)\na b\n`id`\n--flag\n"
    refute File.exists?(Path.join(cli.cwd, "sentinel"))
  end

  test "exit status, merged stderr, environment and redaction", %{cli: cli} do
    assert {:error, %T3.Error{kind: :cli, code: 7, details: %{output: "failure details"}}} =
             CLI.run(cli, ["fail"])

    assert {:ok, result} = CLI.run(%{cli | env: [{"T3_TEST_VALUE", "private-value"}]}, ["env"])
    assert result.output == "private-value"
    assert {:ok, %{output: ""}} = CLI.run(%{cli | env: [{"HOME", nil}]}, ["home"])
    refute inspect(result) =~ "private-value"
    refute inspect(%{cli | env: [{"SECRET", "private-value"}]}) =~ "private-value"
  end

  test "deadline, missing executable and output cap", %{cli: cli} do
    assert {:error, %{code: :timeout}} = CLI.run(%{cli | timeout: 20}, ["wait"])
    assert {:error, %{code: :output_limit}} = CLI.run(%{cli | max_output_bytes: 10}, ["flood"])
    assert {:error, %{code: :not_found}} = CLI.version(CLI.new(executable: "/missing/t3"))
  end

  test "finite stdin input and explicit streaming stdin EOF", %{cli: cli} do
    assert {:ok, %{output: "hello world"}} = CLI.run(cli, ["stdin"], input: ["hello ", "world"])
    assert {:ok, %{output: ""}} = CLI.run(cli, ["stdin"])

    other_owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    try do
      assert {:ok, %{output: "owned by caller"}} =
               CLI.run(cli, ["stdin"], input: "owned by caller", owner: other_owner)
    after
      send(other_owner, :stop)
    end

    {:ok, runner} = CLI.stream(cli, ["stdin"])
    assert :ok = CLI.write(runner, "interactive")
    assert_receive {:t3_cli, ^runner, {:data, "interactive"}}, 1000
    assert :ok = CLI.close_stdin(runner)
    assert_receive {:t3_cli, ^runner, {:exit, %{exit_status: 0, output: "interactive"}}}, 1000
  end

  test "timeout and cancellation terminate the actual executable", %{cli: cli} do
    {:ok, runner} = CLI.stream(%{cli | timeout: 200}, ["wait"])
    {:ok, os_pid} = CLI.os_pid(runner)
    assert_receive {:t3_cli, ^runner, {:error, %{code: :timeout}}}, 1000
    assert_dead(os_pid)
    {:ok, runner} = CLI.stream(cli, ["wait"])
    {:ok, os_pid} = CLI.os_pid(runner)
    :ok = CLI.cancel(runner)
    assert_dead(os_pid)
  end

  @tag capture_log: true
  test "owner death terminates its executable", %{cli: cli} do
    test = self()

    owner =
      spawn(fn ->
        {:ok, runner} = CLI.stream(cli, ["wait"])
        {:ok, os_pid} = CLI.os_pid(runner)
        send(test, {:os_pid, os_pid})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:os_pid, os_pid}, 1000
    Process.exit(owner, :kill)
    assert_dead(os_pid)
  end

  defp assert_dead(os_pid, attempts \\ 50) do
    {_output, status} =
      System.cmd("/bin/kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true)

    cond do
      status != 0 ->
        :ok

      attempts > 0 ->
        Process.sleep(10)
        assert_dead(os_pid, attempts - 1)

      true ->
        flunk("external process #{os_pid} survived cleanup")
    end
  end

  test "stream events and cancellation", %{cli: cli} do
    assert {:ok, runner} = CLI.stream(cli, ["hello"])
    assert_receive {:t3_cli, ^runner, {:data, "hello\n"}}, 1000
    assert_receive {:t3_cli, ^runner, {:exit, %{exit_status: 0}}}, 1000
    assert {:ok, runner} = CLI.stream(cli, ["wait"])
    assert :ok = CLI.cancel(runner)
    assert_receive {:t3_cli, ^runner, {:error, %{code: :cancelled}}}
  end
end
