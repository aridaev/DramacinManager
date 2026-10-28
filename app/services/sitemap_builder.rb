# Membangun sitemap index + bagian: "pages" (beranda, terbaru, genre, halaman penyedia) dan satu bagian per penyedia
# (semua judul di beranda penyedia tsb). Dipakai SeoController dan IndexNowSubmitter.
class SitemapBuilder
  PER_PROVIDER_MAX = 500

  def initialize(base_url:, prefix: "")
    @base = base_url.to_s.chomp("/")
    @prefix = prefix.to_s
  end

  def providers = @providers ||= Provider.enabled.supported.by_latency.to_a

  def index
    today = Date.current.iso8601
    parts = [ "pages" ] + providers.map(&:slug)
    body = parts.map { |p| "  <sitemap><loc>#{h url("/sitemap-#{p}.xml")}</loc><lastmod>#{today}</lastmod></sitemap>" }.join("\n")
    %(<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n#{body}\n</sitemapindex>\n)
  end

  def part(name)
    urls = name == "pages" ? page_urls : provider_urls(name)
    return nil if urls.nil?
    urlset(urls)
  end

  # Semua URL (untuk IndexNow). Judul drama dibatasi agar payload ≤ 10.000 URL.
  def all_urls(limit: 9_000)
    list = page_urls.map(&:first)
    providers.each { |p| list.concat(Array(provider_urls(p.slug)).map(&:first)); break if list.size >= limit }
    list.uniq.first(limit)
  end

  def sitemap_index_url = url("/sitemap.xml")

  private
  def page_urls
    today = Date.current.iso8601
    list = [ [ url("/"), today, "daily", "1.0" ], [ url("/latest"), today, "daily", "0.9" ], [ url("/genre"), today, "weekly", "0.7" ] ]
    Template::V1::BaseController::GENRES.each { |g| list << [ url("/genre/#{g}"), today, "daily", "0.8" ] }
    providers.each { |p| list << [ url("/nonton/#{p.slug}"), today, "daily", "0.9" ] }
    list
  end

  def provider_urls(slug)
    provider = providers.find { |p| p.slug == slug }
    return nil unless provider
    catalog = DracinApi::Catalog.for(provider)
    items = catalog.home.flat_map(&:items).uniq(&:id).first(PER_PROVIDER_MAX)
    today = Date.current.iso8601
    items.map { |d| [ url("/#{provider.slug}/drama/#{d.id}"), today, "weekly", "0.7" ] }
  rescue DracinApi::Error => e
    Rails.logger.warn("[Sitemap] #{slug}: #{e.class} #{e.message}")
    []
  end

  def urlset(urls)
    body = urls.map { |loc, mod, freq, pri| "  <url><loc>#{h loc}</loc><lastmod>#{mod}</lastmod><changefreq>#{freq}</changefreq><priority>#{pri}</priority></url>" }.join("\n")
    %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n#{body}\n</urlset>\n)
  end

  def url(path) = "#{@base}#{@prefix}#{path == '/' && @prefix.present? ? '' : path}"
  def h(s) = ERB::Util.html_escape(s)
end
