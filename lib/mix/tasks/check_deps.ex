defmodule Mix.Tasks.CheckDeps do
  @moduledoc """
  Checks for required system dependencies.

  This task verifies that `fd` and `exiftool` are installed and available
  in the system PATH. It reports version information for each tool when
  available.

  ## Usage

      mix check_deps

  ## Exit Codes

    * 0 - All dependencies are present
    * 1 - One or more dependencies are missing

  """
  @shortdoc "Checks for required system dependencies (fd, exiftool)"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Checking system dependencies...")
    Mix.shell().info("")

    fd_ok = check_fd()
    exiftool_ok = check_exiftool()

    Mix.shell().info("")

    if fd_ok and exiftool_ok do
      Mix.shell().info("✓ All system dependencies are installed")
      :ok
    else
      Mix.shell().error("✗ Missing required system dependencies")
      Mix.shell().info("")
      Mix.shell().info("Installation instructions:")

      unless fd_ok do
        Mix.shell().info("  fd:       https://github.com/sharkdp/fd")
        Mix.shell().info("            brew install fd (macOS)")
        Mix.shell().info("            apt install fd-find (Debian/Ubuntu)")
      end

      unless exiftool_ok do
        Mix.shell().info("  exiftool: https://exiftool.org/")
        Mix.shell().info("            brew install exiftool (macOS)")
        Mix.shell().info("            apt install libimage-exiftool-perl (Debian/Ubuntu)")
      end

      System.halt(1)
    end
  end

  defp check_fd do
    case System.cmd("fd", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = String.trim(output)
        Mix.shell().info("✓ fd:       #{version}")
        true

      _ ->
        Mix.shell().error("✗ fd:       not found")
        false
    end
  rescue
    _ ->
      Mix.shell().error("✗ fd:       not found")
      false
  end

  defp check_exiftool do
    case System.cmd("exiftool", ["-ver"], stderr_to_stdout: true) do
      {output, 0} ->
        version = String.trim(output)
        Mix.shell().info("✓ exiftool: #{version}")
        true

      _ ->
        Mix.shell().error("✗ exiftool: not found")
        false
    end
  rescue
    _ ->
      Mix.shell().error("✗ exiftool: not found")
      false
  end
end
