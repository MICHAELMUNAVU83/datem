defmodule DatemWeb.PassesLive.ItemPassDecision do
  use DatemWeb, :live_view
  alias Datem.Passes

  @impl true
  def mount(%{"token" => token, "action" => action}, _session, socket) do
    pass = Passes.get_item_pass_by_token(token)
    result = pass && action in ["approve", "deny"] && Passes.decide_item_pass(pass, decision_for(action))

    {:ok, assign(socket, :result, result)}
  end

  @impl true
  def render(%{result: {:ok, pass}} = assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-md rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
        <p class="text-lg font-semibold text-gray-900">Request {pass.status}.</p>
        <p class="mt-2 text-sm text-gray-600">
          The item pass for "{pass.item_name}" requested by {pass.requested_by.name} has been recorded.
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-md rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
        <p class="text-gray-700">This link is invalid or has already been used.</p>
      </div>
    </div>
    """
  end

  defp decision_for("approve"), do: "approved"
  defp decision_for("deny"), do: "denied"
end
