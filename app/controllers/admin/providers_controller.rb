class Admin::ProvidersController < Admin::BaseController
  FILTERS = %w[all short_drama chinese_drama enabled disabled].freeze

  def index
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"
    @providers = filtered_scope(@filter).includes(:api_source).ordered
    @total = Provider.count
    @enabled_count = Provider.enabled.count
    @api_configured = Setting.dracin_api_key.present?
  end

  def update
    provider = Provider.find(params[:id])
    provider.update!(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    redirect_back_or_to admin_providers_path, notice: t("admin.providers.#{provider.enabled? ? 'enabled' : 'disabled'}_notice", name: provider.name)
  end

  def enable_all
    count = Provider.update_all(enabled: true, updated_at: Time.current)
    redirect_to admin_providers_path, notice: t("admin.providers.enable_all_notice", count: count)
  end

  def disable_all
    count = Provider.update_all(enabled: false, updated_at: Time.current)
    redirect_to admin_providers_path, notice: t("admin.providers.disable_all_notice", count: count)
  end

  def sync_status
    client = DracinApi::Client.from_settings
    return redirect_to admin_providers_path, alert: t("admin.providers.api_key_missing") unless client.configured?

    data = client.status
    entries = Array(data["platforms"] || data["providers"])
    count = Provider.apply_status!(entries)
    online = entries.count { |e| Provider::ONLINE_STATUSES.include?(e["status"].to_s) }
    redirect_to admin_providers_path, notice: t("admin.providers.sync_success", count: count, online: online, offline: count - online)
  rescue DracinApi::Error => e
    redirect_to admin_providers_path, alert: t("admin.providers.sync_failed", error: e.message)
  end

  private
  def filtered_scope(filter)
    case filter
    when "short_drama", "chinese_drama" then Provider.where(category: filter)
    when "enabled" then Provider.enabled
    when "disabled" then Provider.disabled
    else Provider.all
    end
  end
end
