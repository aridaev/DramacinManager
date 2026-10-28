class Template::V1::HomeController < Template::V1::BaseController
  before_action :require_provider!

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
end
