class Template::V1::HomeController < Template::V1::BaseController
  before_action :require_provider!, except: :amp
  before_action :amp_redirect_from_google, only: :index

  def index
    @sections = catalog.home
    @hero = @sections.flat_map(&:items).first(6)
  end

  def search
    @query = params[:q].to_s.strip
    @page = [ params[:page].to_i, 1 ].max
    @result = @query.present? ? catalog.search(@query, page: @page) : DracinApi::Catalog::Page.new(items: [], page: 1, has_more: false)
    render :browse
  end

  def genres; end

  # Halaman AMP ringan (logo, banner iklan, tombol login/nonton). Hanya untuk instance dengan AMP aktif.
  def amp
    return head :not_found unless current_instance&.amp_enabled?
    render :amp, layout: false, content_type: "text/html"
  end

  # Gabungan semua section beranda (untuk menu "Terbaru" bawaan instance).
  def latest
    @heading = t("template.v1.latest_title")
    items = catalog.home.flat_map(&:items).uniq { |d| d.id }
    @result = DracinApi::Catalog::Page.new(items: items, page: 1, has_more: false)
    render :browse
  end

  def genre
    @genre = params[:genre].to_s.parameterize
    @page = [ params[:page].to_i, 1 ].max
    @result = catalog.genre(@genre, page: @page)
    render :browse
  end

  private
  # Kunjungan pertama dari Google → tampilkan /amp dulu; dari AMP tombol "Nonton" membawa ?from=amp ke beranda.
  GOOGLE_REF = %r{\Ahttps?://([a-z0-9-]+\.)*google\.[a-z.]+/}i
  def amp_redirect_from_google
    return unless on_instance_host? && current_instance&.amp_google_redirect?
    return if params[:from] == "amp" || session[:amp_seen] || params[:provider].present?
    return unless request.get? && request.referer.to_s.match?(GOOGLE_REF)
    session[:amp_seen] = true
    redirect_to template_v1_amp_path
  end
end
