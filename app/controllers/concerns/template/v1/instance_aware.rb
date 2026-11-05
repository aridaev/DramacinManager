# Membuat template v1 sadar-instance: di domain kustom (InstanceHost) atau mode pratinjau
# (?preview_instance=<nama>), branding diambil dari Instance dan URL template dibuat relatif ke root.
module Template::V1::InstanceAware
  extend ActiveSupport::Concern

  ROUTE_NAMES = %w[root amp search genres latest genre stream subtitle drama watch provider_home sitemap robots member member_login member_register member_logout member_deposit member_share].freeze

  # Mengganti helper template_v1_*_path → site_*_path saat melayani domain instance.
  # Dipakai di controller template v1 (termasuk streams/subtitles) dan sebagai view helper.
  module RouteOverrides
    def on_instance_host? = InstanceHost.resolve(request.env).present?

    # Kunci template aktif: instance di domain → instance pratinjau → scope URL (/template/vN) → v1.
    def tpl
      @tpl ||= begin
        key = InstanceHost.resolve(request.env)&.template_key ||
              (respond_to?(:current_instance, true) ? current_instance&.template_key : nil) ||
              params[:tpl].presence || "v1"
        Instance::TEMPLATES.key?(key) ? key : "v1"
      end
    end

    ROUTE_NAMES.each do |name|
      define_method("template_v1_#{name}_path") do |*args, **opts|
        if on_instance_host? then public_send("site_#{name}_path", *args, **opts)
        elsif tpl != "v1"    then public_send("template_#{tpl}_#{name}_path", *args, **opts)
        else super(*args, **opts)
        end
      end
    end

    # URL item navbar/footer instance: relatif ke root template (di domain sendiri = "/", di host utama = /template/v1).
    def tv1_nav_url(url)
      u = url.to_s.strip
      return "#" if u.blank? || u == "#"
      return u if u.match?(%r{\A(https?:)?//|\Amailto:|\Atel:}i)
      u = "/#{u}" unless u.start_with?("/")
      on_instance_host? ? u : "/template/#{tpl}#{u == '/' ? '' : u}"
    end
  end

  included do
    include RouteOverrides
    helper RouteOverrides
    helper_method :tpl, :current_instance, :tv1_site_name, :tv1_meta_description, :tv1_icon_url, :tv1_logo_url,
                  :tv1_nav_items, :tv1_footer_text, :tv1_footer_links, :tv1_copyright, :current_member, :member_session_key, :show_ads?, :guest_adfree?, :guest_adfree_until, :adfree_now?, :adfree_nav?, :share_reward_minutes
    before_action :set_preview_instance
    before_action :require_active_instance!
  end

  def host_instance = InstanceHost.resolve(request.env)

  def current_instance
    return @current_instance if defined?(@current_instance)
    @current_instance = host_instance || preview_instance
  end

  def tv1_site_name        = current_instance&.app_name.presence || current_instance&.localized("site_title").presence || t("template.v1.site_name")
  def tv1_meta_description = current_instance&.localized("meta_description").presence || t("template.v1.meta_description")
  def tv1_icon_url         = current_instance&.icon_url.presence || "/icon.svg"
  def tv1_logo_url         = current_instance&.logo_url.presence
  # Tombol "Bebas Iklan" kini tombol tersendiri (partial shared/adfree_nav), bukan lagi item menu biasa.
  def tv1_nav_items
    return [] unless current_instance
    current_instance.nav_items.select { |it| it["enabled"] != false }
  end

  def default_nav_items
    [ { "label" => I18n.t("template.v1.nav.home"), "url" => "/" }, { "label" => I18n.t("template.v1.nav.genre"), "url" => "/genre" }, { "label" => I18n.t("template.v1.nav.latest", default: "Terbaru"), "url" => "/latest" } ]
  end

  # Akun penonton (Member) per instance — sesi terpisah dari Devise.
  def member_session_key = "tv1_member_#{current_instance&.id}"
  def current_member
    return @current_member if defined?(@current_member)
    @current_member = (current_instance&.members_enabled? && (id = session[member_session_key])) ? current_instance.members.find_by(id: id) : nil
  end
  # Iklan pra-tayang tampil bila diaktifkan dan penonton bukan member bebas iklan.
  # Hadiah share: bebas iklan sementara untuk siapa pun (tamu atau member), disimpan di cookie bertanda tangan
  # per instance. Pembatasan frekuensi (SHARE_COOLDOWN) dijaga server di MembersController#share.
  SHARE_REWARD   = 15.minutes
  SHARE_COOLDOWN = 1.hour

  def share_reward_minutes = (SHARE_REWARD / 60).to_i
  def share_cookie_key = "tv1_share_#{current_instance&.id}"
  def guest_adfree_until
    return @guest_adfree_until if defined?(@guest_adfree_until)
    ts = cookies.signed[share_cookie_key].to_i
    @guest_adfree_until = ts > Time.current.to_i ? Time.zone.at(ts) : nil
  end
  def guest_adfree? = guest_adfree_until.present?
  def adfree_now? = !!(current_member&.adfree? || guest_adfree?)
  # Tombol navbar hanya berguna bila fitur member aktif dan iklan memang tampil.
  def adfree_nav? = !!(current_instance&.members_enabled? && current_instance.ads_active?)
  def show_ads? = current_instance&.ads_active? && !adfree_now?
  def tv1_footer_text      = current_instance&.localized("footer_text").presence || t("template.v1.footer.tagline")
  def tv1_footer_links     = current_instance ? current_instance.footer_link_list : []
  def tv1_copyright        = current_instance&.copyright.presence

  private
  # Pratinjau branding tanpa domain: /template/v1?preview_instance=<nama> (hanya user login; =0 untuk keluar).
  def set_preview_instance
    return if on_instance_host? || !params.key?(:preview_instance)
    name = params[:preview_instance].to_s
    session[:tv1_preview] = (name.present? && name != "0") ? name : nil
    # lookup_context (dan tpl/current_instance) sudah dibangun saat process() sebelum before_action ini.
    remove_instance_variable(:@current_instance) if defined?(@current_instance)
    @tpl = @_tpl_prefixes = @_lookup_context = nil
  end

  def preview_instance
    name = session[:tv1_preview].presence
    return nil if name.nil? || !user_signed_in?
    Instance.find_by(name: name) || (session[:tv1_preview] = nil)
  end

  def require_active_instance!
    inst = host_instance
    return if inst.nil? || inst.active?
    render "template/v1/shared/inactive", status: :service_unavailable, layout: false
  end
end
