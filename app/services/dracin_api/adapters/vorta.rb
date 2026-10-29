module DracinApi
  module Adapters
    # Hub Vorta (https://api.vorta.tech) — satu adapter untuk semua kategori; slug provider = category_p.
    # Auth HMAC-SHA256 per request: X-Timestamp (ms) + X-Signature = hex HMAC("GET:<path?query>:<ts>", secret).
    #   /api/v2/categories                             → { data: [ { name, display_name, logo_url, is_active } ] } (tanpa auth)
    #   /api/v2/home?category_p=&lang=                 → { data: [ { id, title, cover, synopsis, status, chapters, genres } ] }
    #   /api/v2/search?category_p=&q=&lang=&page=      → { data, page, hasMore }
    #   /api/v2/detail?category_p=&id=&lang=           → { data: { ..., total_episodes, chapters: [ { id, index, is_locked } ] } }
    #   /api/v2/video?category_p=&id=&chapterId=&lang= → { data: { streams: [ { quality, url } ], subtitles: [ { languageCode, language, url } ] } }
    class Vorta < Base
      default_host "https://api.vorta.tech"

      attr_reader :source

      # Kategori aktif sebuah sumber (diisi saat test/sync, cache 12 jam) — dipakai untuk memutuskan fallback.
      def self.categories(source)
        key = [ "vorta", "categories", source.id ]
        Rails.cache.read(key) || begin
          names = Array(Http.get_json("#{source.base_url}/api/v2/categories")["data"])
                    .select { |c| c["is_active"] != false }.map { |c| c["name"].to_s }
          store_categories(source, names) if names.any?
          names
        rescue DracinApi::Error
          []
        end
      end

      def self.store_categories(source, names)
        Rails.cache.write([ "vorta", "categories", source.id ], Array(names), expires_in: 12.hours)
      end

      # Adapter cadangan untuk provider non-Vorta yang kategorinya tersedia di salah satu sumber HMAC.
      def self.fallback_for(provider, lang: nil)
        return nil if provider.adapter_slug == "vorta"
        src = ApiSource.hmac.enabled.ordered.detect { |s| s.configured? && categories(s).include?(provider.slug) }
        src && new(provider, lang: lang, source: src)
      end

      def initialize(provider, api_key: nil, lang: nil, source: nil)
        @source = source || (provider.api_source if provider.api_source&.hmac?) || ApiSource.hmac.enabled.ordered.first
        super(provider, api_key: @source&.api_key.presence || api_key, lang: lang)
      end

      # Host selalu base_url sumber HMAC (api_url provider bisa berisi host DracinAPI bila slug tumpang tindih).
      def host
        @host ||= begin
          url = source&.base_url.presence || self.class.default_host
          URI.parse(url).then { |u| "#{u.scheme}://#{u.host}" }
        end
      end

      def home
        items = Array(get("/api/v2/home", category_p: slug, lang: lang)["data"]).map { |d| to_drama(d) }
        [ section(I18n.t("template.v1.sections.for_you"), items) ]
      end

      def search(q, page: 1)
        data = get("/api/v2/search", category_p: slug, q: q, lang: lang, page: page)
        page(Array(data["data"]).map { |d| to_drama(d) }, page: page, has_more: data["hasMore"])
      end

      def detail(id)
        d = get("/api/v2/detail", category_p: slug, id: id, lang: lang)["data"] || {}
        eps = d["chapters"].is_a?(Array) && d["chapters"].any? ? d["chapters"].size : d["total_episodes"].to_i
        to_drama(d.merge("id" => d["id"].presence || id), episodes: eps.nonzero?)
      end

      def episodes(id)
        d = get("/api/v2/detail", category_p: slug, id: id, lang: lang)["data"] || {}
        Array(d["chapters"]).map do |c|
          episode(number: c["index"], title: c["title"].presence || "EP #{c['index']}", locked: c["is_locked"] ? true : false,
                  payload: { "chapter_id" => c["id"].to_s })
        end
      end

      def play(id, ep)
        item = find_episode(id, ep)
        chapter_id = item&.payload.to_h["chapter_id"].presence || ep
        v = get("/api/v2/video", category_p: slug, id: id, chapterId: chapter_id, lang: lang)["data"] || {}
        sources = Array(v["streams"]).filter_map { |s| s["url"].present? ? { label: s["quality"].to_s.presence || s["resolution"].to_s, url: s["url"] } : nil }
        return nil if sources.empty?
        best = sources.max_by { |s| s[:label][/\d+/].to_i }
        subs = Array(v["subtitles"]).filter_map do |s|
          s["url"].present? ? subtitle(lang: s["languageCode"].presence || s["language"], url: s["url"], label: s["language"]) : nil
        end
        stream(url: best[:url], episode: ep, sources: sources, subtitles: subs)
      end

      private
      # Tanda tangan dihitung dari request_uri persis seperti yang dikirim, jadi URL dirakit di sini.
      def get(path, params = {})
        raise MissingApiKey, I18n.t("dracin_api.errors.missing_api_key") unless source&.api_key.present?
        memo(path, params) do
          uri = URI.parse("#{host}#{path}")
          uri.query = URI.encode_www_form(params.compact) if params.present?
          Http.get_json(uri.to_s, headers: source.hmac_headers("GET", uri.request_uri))
        end
      end

      # Di home/search `chapters` = jumlah episode (string); di detail `chapters` = array bab.
      def to_drama(d, **extra)
        ch = d["chapters"]
        drama(id: d["id"], title: d["title"], cover: d["cover"], synopsis: d["synopsis"],
              episodes: (ch.is_a?(Array) ? ch.size : ch.to_i).nonzero?, genres: Array(d["genres"]).presence || Array(d["tags"]),
              language: nil, rating: nil, year: nil, status: d["status"].presence, **extra)
      end
    end
  end
end
