defmodule JidoCodemodeWeb.Links do
  @moduledoc """
  Outbound links, with the attribution Odoo expects.

  Odoo only credits known `utm_source` values: `agentic_bi` (source 72) is the
  public landing's funnel, `demo_agentic_bi` (source 73) is invited testers. The
  CRM reads only `utm_source`; `utm_medium` labels GA4.
  """

  @calendar "https://superdev.mx/calendar/"

  @doc "Exploratory-call link for public landing visitors."
  @spec calendar(:landing | :demo_invitee) :: String.t()
  def calendar(:landing), do: @calendar <> "?utm_source=agentic_bi&utm_medium=landing"
  def calendar(:demo_invitee), do: @calendar <> "?kind=demo&utm_source=demo_agentic_bi"

  @spec ai_readiness() :: String.t()
  def ai_readiness, do: "https://superdev.mx/ai-readiness/"

  @spec privacy() :: String.t()
  def privacy, do: "https://superdev.mx/privacidad/"

  @spec demos_privacy() :: String.t()
  def demos_privacy, do: "https://superdev.mx/privacidad/#demos"

  @spec superdev() :: String.t()
  def superdev, do: "https://superdev.mx/"

  @spec business_intelligence() :: String.t()
  def business_intelligence, do: "https://superdev.mx/business-intelligence/"

  @doc """
  The invitation service's self-serve request form, served by its Worker on this
  host. `nil` until the service is connected: the page then offers the call.
  """
  @spec access_request() :: String.t() | nil
  def access_request do
    if JidoCodemode.DemoAccess.enabled?(), do: "/invite/solicitar"
  end
end
