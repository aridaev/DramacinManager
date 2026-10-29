class Template::V1::BaseController < ApplicationController
  skip_before_action :authenticate_user!
  include Template::V1::InstanceAware
  layout -> { "template/#{tpl}" }

  before_action :load_providers
  before_action :select_provider
  after_action :track_visit, if: -> { request.get? && response.status == 200 && current_instance }

  helper_method :current_provider, :enabled_providers, :catalog

  rescue_from DracinApi::Error, with: :render_api_error

  GENRES = %w[romance action thriller comedy fantasy revenge ceo rebirth].freeze

  # View dicari di app/views/template/<tpl>/... dulu, lalu fallback ke template/v1/...
  def _prefixes
    @_tpl_prefixes ||= tpl == "v1" ? super : super.flat_map { |p| p.start_with?("template/v1/") ? [ p.sub("template/v1/", "template/#{tpl}/"), p ] : [ p ] }
  end

private
# Statistik pengunjung per instance: dicatat setelah respons sukses, dieksekusi async supaya tidak memperlambat halaman.
def track_visit
  return if request.xhr? || !request.format.html?
  kind = { "home#index" => "home", "home#search" => "search", "home#genre" => "genre", "home#genres" => "genre",
           "dramas#show" => "drama", "dramas#watch" => "watch", "members#show" => "member" }["#{controller_name}##{action_name}"] || "other"
  attrs = Visit.attributes_from(request, instance: current_instance, kind: kind, provider: current_provider&.slug, drama_id: (params[:id] if kind.in?(%w[drama watch])))
  VisitTrackJob.perform_later(attrs)
rescue => e
  Rails.logger.warn("[Visit] #{e.class}: #{e.message}")
end

  def load_providers
    # Hanya platform yang diaktifkan admin DAN sudah punya adapter API.
    @enabled_providers = Provider.enabled.supported.by_latency.to_a
  end
  attr_reader :enabled_providers

  def select_provider
    slug = params[:provider].presence || session[:tv1_provider]
    @provider_from_path = params[:provider].present?
    @current_provider = enabled_providers.find { |p| p.slug == slug } || enabled_providers.first
    session[:tv1_provider] = @current_provider&.slug
  end
  attr_reader :current_provider

  def catalog
    @catalog ||= DracinApi::Catalog.for(current_provider, lang: I18n.locale)
  end

  def require_provider!
    render "template/v1/shared/no_provider", status: :service_unavailable if current_provider.nil?
  end

  def render_api_error(error)
    Rails.logger.warn("[DracinApi] #{current_provider&.slug}: #{error.class} #{error.message}")
    @error = error
    @error_kind = error.is_a?(DracinApi::MissingApiKey) ? :missing_api_key : :api_error
    response.set_header("Retry-After", "30")
    render "template/v1/shared/api_error", status: :service_unavailable
  end
end
