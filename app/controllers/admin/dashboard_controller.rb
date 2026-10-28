class Admin::DashboardController < Admin::BaseController
  def show
    @sources = ApiSource.ordered.to_a
    @sources_count = @sources.size
    @fastest = Provider.enabled.supported.where.not(last_latency_ms: nil).by_latency.limit(8).to_a
    @total_providers = Provider.count
    @enabled_providers = Provider.enabled.count
    @supported_providers = Provider.supported.count
    @online_providers = Provider.where(last_status: Provider::ONLINE_STATUSES).count
    @offline_providers = Provider.where.not(last_status: [ nil, *Provider::ONLINE_STATUSES ]).count
    @last_checked_at = Provider.maximum(:last_checked_at)
    @api_key = Setting.dracin_api_key
    @base_url = Setting.dracin_api_base_url
  end
end
