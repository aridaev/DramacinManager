# Pengaturan Situs (admin): token Cloudflare global, IP VPS, mode SSL, dan kebijakan instance untuk user.
class Admin::SiteSettingsController < Admin::BaseController
  def edit
    @token = Setting.cloudflare_api_token
    @account_id = Setting.cloudflare_account_id
    @auth_email = Setting.cloudflare_auth_email
    @vps_ip = Setting.vps_ip.presence || detected_ip
    @ssl_mode = Setting.cloudflare_ssl_mode
    @users_can_create = Setting.users_can_create_instances?
    @max_per_user = Setting.max_instances_per_user
    @token_status = Setting.get(Setting::CF_TOKEN_STATUS)
    @tp_key = Setting.tokenplus_api_key
    @tp_model = Setting.tokenplus_model
    @tp_status = Setting.get(Setting::TP_STATUS)
    @tp_models = (Rails.cache.read("tokenplus_models") || []) | TokenPlusClient::SUGGESTED_MODELS
    @gsc = Setting.gsc_verification
    @indexnow_key = Setting.indexnow_key
    @indexnow_last = Setting.get(Setting::INDEXNOW_LAST)
    @main_host = Setting.main_host
  end

  def update
    p = params.fetch(:site, {}).permit(:cloudflare_api_token, :cloudflare_account_id, :cloudflare_auth_email, :vps_ip, :cloudflare_ssl_mode, :users_can_create_instances, :max_instances_per_user, :tokenplus_api_key, :tokenplus_model, :gsc_verification, :main_host)
    Setting.set(Setting::CF_API_TOKEN, p[:cloudflare_api_token].to_s.strip) if p[:cloudflare_api_token].present?
    Setting.set(Setting::CF_ACCOUNT_ID, p[:cloudflare_account_id].to_s.strip)
    Setting.set(Setting::CF_AUTH_EMAIL, p[:cloudflare_auth_email].to_s.strip.downcase)
    Setting.set(Setting::VPS_IP, p[:vps_ip].to_s.strip)
    gsc = p[:gsc_verification].to_s.strip; gsc = $1 if gsc =~ /content=["']([^"']+)["']/
    Setting.set(Setting::GSC_VERIFY, gsc)
    Setting.set(Setting::MAIN_HOST, p[:main_host].to_s.strip.downcase.sub(%r{\Ahttps?://}, "").sub(%r{/.*}, "").presence || "dracin.aridaev.com")
    Setting.set(Setting::TP_API_KEY, p[:tokenplus_api_key].to_s.strip) if p[:tokenplus_api_key].present?
    Setting.set(Setting::TP_MODEL, p[:tokenplus_model].to_s.strip.presence || TokenPlusClient::DEFAULT_MODEL)
    Setting.set(Setting::CF_SSL_MODE, %w[flexible full strict].include?(p[:cloudflare_ssl_mode]) ? p[:cloudflare_ssl_mode] : "flexible")
    Setting.set(Setting::USERS_CAN_CREATE, ActiveModel::Type::Boolean.new.cast(p[:users_can_create_instances]) ? "1" : "0")
    Setting.set(Setting::MAX_PER_USER, [ p[:max_instances_per_user].to_i, 0 ].max.to_s)
    redirect_to edit_admin_site_settings_path, notice: t("admin.site_settings.updated")
  end

  def test_cloudflare
    client = CloudflareClient.from_settings
    return redirect_to edit_admin_site_settings_path, alert: t("admin.site_settings.token_missing") unless client.configured?
    v = client.verify_token
    accounts = client.accounts
    if Setting.cloudflare_account_id.blank? && accounts.size == 1
      Setting.set(Setting::CF_ACCOUNT_ID, accounts.first["id"])
    end
    Setting.set(Setting::CF_TOKEN_STATUS, "ok #{v['status']} (#{client.global_key? ? 'Global API Key' : 'API Token'}) · #{accounts.size} akun · #{I18n.l(Time.current, format: :short)}")
    redirect_to edit_admin_site_settings_path, notice: t("admin.site_settings.token_ok", status: v["status"], accounts: accounts.map { |a| a["name"] }.join(", "))
  rescue CloudflareClient::Error => e
    Setting.set(Setting::CF_TOKEN_STATUS, "gagal: #{e.message.truncate(80)}")
    redirect_to edit_admin_site_settings_path, alert: t("admin.site_settings.token_failed", error: e.message)
  end

  def test_tokenplus
    client = TokenPlusClient.from_settings
    return redirect_to edit_admin_site_settings_path, alert: t("admin.site_settings.tp_missing") unless client.configured?
    models = client.models
    Rails.cache.write("tokenplus_models", models, expires_in: 1.day)
    Setting.set(Setting::TP_STATUS, "ok · #{models.size} model · #{I18n.l(Time.current, format: :short)}")
    redirect_to edit_admin_site_settings_path, notice: t("admin.site_settings.tp_ok", count: models.size)
  rescue TokenPlusClient::Error => e
    Setting.set(Setting::TP_STATUS, "gagal: #{e.message.truncate(80)}")
    redirect_to edit_admin_site_settings_path, alert: t("admin.site_settings.tp_failed", error: e.message)
  end

  def clear_tokenplus
    Setting.set(Setting::TP_API_KEY, nil); Setting.set(Setting::TP_STATUS, nil)
    redirect_to edit_admin_site_settings_path, notice: t("admin.site_settings.tp_cleared")
  end

  def submit_indexnow
    total = 0; code = nil
    Instance::TEMPLATES.each_key { |tpl| r = IndexNowSubmitter.new(nil, host: Setting.main_host, tpl: tpl).call; total += r[:count]; code = r[:code] }
    redirect_to edit_admin_site_settings_path(anchor: "seo"), notice: t("admin.site_settings.indexnow_ok", count: total, code: code)
  rescue IndexNowSubmitter::Error => e
    redirect_to edit_admin_site_settings_path(anchor: "seo"), alert: t("admin.site_settings.indexnow_failed", error: e.message)
  end

  def clear_cloudflare
    Setting.set(Setting::CF_API_TOKEN, nil)
    Setting.set(Setting::CF_TOKEN_STATUS, nil)
    redirect_to edit_admin_site_settings_path, notice: t("admin.site_settings.token_cleared")
  end

  private
  # IP publik VPS dari interface default (tanpa panggilan eksternal).
  def detected_ip
    Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? && !a.ipv4_private? }&.ip_address
  rescue StandardError
    nil
  end
end
