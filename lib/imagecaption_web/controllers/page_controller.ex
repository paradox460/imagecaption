defmodule ImagecaptionWeb.PageController do
  use ImagecaptionWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
