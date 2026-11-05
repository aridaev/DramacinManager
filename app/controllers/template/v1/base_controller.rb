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
    # Hanya platform yang diaktifkan admin, punya adapter API, dan sedang sehat (DracinApi::Health).
    @enabled_providers = Provider.available.by_latency.to_a
  end
  attr_reader :enabled_providers

  # Provider yang diminta tidak sehat/tidak tersedia → pindah ke provider sehat tercepat (bukan halaman error).
  def select_provider
    slug = params[:provider].presence || session[:tv1_provider]
    @provider_from_path = params[:provider].present?
    @current_provider = enabled_providers.find { |p| p.slug == slug }
    if @current_provider.nil? && slug.present? && enabled_providers.any?
      @current_provider = enabled_providers.first
      if @provider_from_path && request.get?
        # ID judul milik provider yang diminta tidak berlaku di provider lain: klien non-HTML (bot/API) cukup diberi 503.
        unless request.format.html?
          response.set_header("Retry-After", "300")
          return head(:service_unavailable)
        end
        flash[:notice] = t("template.v1.provider_unavailable", provider: Provider.find_by(slug: slug)&.name || slug, to: @current_provider.name)
        return redirect_to url_for(params.permit!.to_h.merge(provider: @current_provider.slug, only_path: true))
      end
    end
    @current_provider ||= enabled_providers.first
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
    @error_kind = error.is_a?(DracinApi::MissingApiKey) ? :missing_api_key : DracinApi::Failure.kind(error)
    @alternative_providers = enabled_providers.reject { |p| p == current_provider }.first(8)
    response.set_header("Retry-After", "30")
    render "template/v1/shared/api_error", status: :service_unavailable
  end
end
