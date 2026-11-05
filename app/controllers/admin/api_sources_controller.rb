class Admin::ApiSourcesController < Admin::BaseController
  before_action :load_source, only: [ :edit, :update, :destroy, :test, :sync, :make_default ]

  def index
    @sources = ApiSource.ordered.includes(:providers)
    @provider_counts = Provider.group(:api_source_id).count
    @error_stats = ProviderErrorStat.report
    @muted = Provider.where("unavailable_until > ?", Time.current).includes(:api_source).ordered.to_a
  end

  def new
    @source = ApiSource.new(auth_mode: "header_x_token", status_path: "/api/status")
  end

  def create
    @source = ApiSource.new(source_params)
    @source.is_default = true if ApiSource.none?
    if @source.save
      redirect_to admin_api_sources_path, notice: t("admin.api_sources.created", name: @source.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = source_params
    attrs.delete(:api_key) if attrs[:api_key].blank? # kosong = jangan ubah key
    if @source.update(attrs)
      redirect_to admin_api_sources_path, notice: t("admin.api_sources.updated", name: @source.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @source.is_default?
      redirect_to admin_api_sources_path, alert: t("admin.api_sources.cannot_delete_default")
    else
      @source.destroy
      redirect_to admin_api_sources_path, notice: t("admin.api_sources.deleted", name: @source.name)
    end
  end

  def make_default
    @source.update!(is_default: true)
    redirect_to admin_api_sources_path, notice: t("admin.api_sources.default_set", name: @source.name)
  end

  # Tes koneksi: GET status_url dengan auth sumber; simpan hasil ringkas.
  def test
    client = DracinApi::Client.from_source(@source)
    return redirect_to admin_api_sources_path, alert: t("admin.api_sources.key_missing") unless client.configured?
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    data = client.status
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
    entries = Array(data["platforms"] || data["providers"] || data["data"])
    @source.update_columns(last_tested_at: Time.current, last_test_result: "ok #{ms}ms, #{entries.size} entri")
    redirect_to admin_api_sources_path, notice: t("admin.api_sources.test_success", ms: ms, count: entries.size)
  rescue DracinApi::Error => e
    @source.update_columns(last_tested_at: Time.current, last_test_result: "gagal: #{e.message.truncate(80)}")
    redirect_to admin_api_sources_path, alert: t("admin.api_sources.test_failed", error: e.message)
  end

  # Sinkron daftar platform dari hub sumber ini → tabel providers (tautkan ke sumber).
  def sync
    client = DracinApi::Client.from_source(@source)
    return redirect_to admin_api_sources_path, alert: t("admin.api_sources.key_missing") unless client.configured?
    data = client.status
    entries = Array(data["platforms"] || data["providers"] || data["data"])
    count = Provider.apply_status!(entries, source: @source)
    redirect_to admin_providers_path, notice: t("admin.api_sources.sync_success", count: count, name: @source.name)
  rescue DracinApi::Error => e
    redirect_to admin_api_sources_path, alert: t("admin.api_sources.test_failed", error: e.message)
  end

  private
  def load_source = @source = ApiSource.find(params[:id])

  def source_params
    params.require(:api_source).permit(:name, :slug, :base_url, :api_key, :auth_mode, :auth_param, :status_path, :enabled, :notes)
  end
end
