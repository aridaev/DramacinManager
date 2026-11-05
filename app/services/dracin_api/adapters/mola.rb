module DracinApi
  module Adapters
    # Hub Mola API (https://api.molatv.id, docs /documentation) — satu gateway untuk ~88 platform drama pendek.
    #   GET /api/{platform}/{action}?...   auth: header X-API-TOKEN (atau Bearer / ?token=)
    # Aksi hampir seragam (search / detail / allepisode / stream[_plain] + beberapa daftar: foryou, terbaru, ranking, ...)
    # tetapi NAMA PARAMETER id/episode/kata kunci dan BENTUK respons berbeda per platform. Karena itu adapter ini generik:
    #   - daftar aksi + parameter tiap platform diambil dari katalog docs (`const ALL_PLATFORMS` di HTML /docs/<slug>,
    #     cache 24 jam; cadangan config/mola_platforms.json);
    #   - respons dinormalisasi dengan mencari kunci yang lazim (bookId/book_id/drama_id/..., title/bookName/..., cover/...,
    #     episodes[].episodeIndex|chapterIndex, qualities[]/url/videoUrl/playUrl).
    # Provider Mola memakai adapter_key "mola"; slug provider = slug platform Mola (bisa sama dengan slug DracinAPI →
    # provider DracinAPI tetap pakai adapter natif, Mola jadi cadangan lewat Adapters.fallback_for).
    # KUOTA: token tester hanya 100 request/hari → beranda dibatasi HOME_MAX section dan set_language 1x/hari.
    class Mola < Base
      default_host "https://api.molatv.id"
      HUB_HOST = "api.molatv.id".freeze
      EXCLUDED = %w[winknovel audiotoon].freeze # novel / campuran audio-komik, bukan drama video
      CHINESE  = %w[iqiyi wetv bstation drakorid lookseries ansflix lupacine dramaqueen drachinreborn].freeze
      HOME_MAX = 2
      CACHE_TTL = 6.hours # home/search/detail/episodes; play tetap PLAY_TTL (URL ber-signature)
      # Aksi daftar (punya param page, tanpa id/kata kunci) berurutan prioritas untuk beranda.
      HOME_PRIORITY = %w[foryou home recommend recomendasi hot trending tren popular populer ranking rankings rank
                         terbaru new baru newest newrelease new_release exclusive original vip alldrama all_drama all drama list].freeze
      NOT_LIST = %w[set_language search detail allepisode episodes stream stream_plain play decrypt decrypt-mp4 subtitle subtitles
                    languages lang session browse_filters category category_dramas audio-play read-novel pages].freeze
      SECTION_TITLES = { "foryou" => :for_you, "home" => :for_you, "recommend" => :for_you, "recomendasi" => :for_you,
                         "hot" => :trending, "trending" => :trending, "tren" => :trending, "popular" => :trending, "populer" => :trending,
                         "ranking" => :trending, "rankings" => :trending, "rank" => :trending,
                         "terbaru" => :latest, "new" => :latest, "baru" => :latest, "newest" => :latest, "newrelease" => :latest, "new_release" => :latest,
                         "dubbing" => :dubbed_latest }.freeze
      ID_KEYS    = %w[bookId book_id drama_id dramaId playlet_id playletId album_id albumId series_id seriesId id db_id vid].freeze
      TITLE_KEYS = %w[title bookName book_name name drama_name dramaName playlet_name album_name].freeze
      COVER_KEYS = %w[cover cover_url coverUrl vertical_poster_url poster poster_url image img thumb thumbnail pic coverWap].freeze
      DESC_KEYS  = %w[summary description synopsis intro introduction desc brief].freeze
      COUNT_KEYS = %w[totalEpisodes total_episodes chapterCount chapter_count episode_count episodeCount totalChapter total_chapters episodes_total].freeze
      EP_NUM_KEYS = %w[episodeIndex chapterIndex episode_index chapter_index index episode ep number sort serial_number].freeze
      EP_ID_KEYS  = %w[episodeId chapterId episode_id chapter_id id vid tv_id].freeze
      URL_KEYS    = %w[url videoUrl video_url playUrl play_url directUrl direct_url m3u8 mp4 src].freeze
      LANG_MAP = { "id" => "id", "en" => "en" }.freeze

      Platform = Struct.new(:slug, :name, :logo, :actions, keyword_init: true) do
        def action?(a) = actions.key?(a)
        def params_of(a) = Array(actions.dig(a, "params")).map { |p| p["name"].to_s }
        def id_param = (params_of("detail").first.presence || params_of("allepisode").first.presence || "book_id")
        def episode_param = (params_of(play_action).find { |n| n != id_param && n =~ /episode|index|^ep$/i } || "episode")
        def keyword_param = (params_of("search").find { |n| n =~ /\A(keyword|word|query|q|key|title|name|search)\z/i } || params_of("search").first || "keyword")
        def play_action = %w[stream_plain stream play].find { |a| action?(a) }
        def episodes_action = %w[allepisode episodes list_episodes].find { |a| action?(a) }
        def lang?(a) = params_of(a).include?("lang")
        def size_param(a) = params_of(a).find { |n| %w[page_size pageSize per_page limit].include?(n) }
        def home_actions
          list = actions.keys.reject { |a| NOT_LIST.include?(a) || params_of(a).any? { |n| ID_KEYS.include?(n) || n =~ /keyword|word|query/ } }
          (HOME_PRIORITY & list).presence&.first(HOME_MAX) || list.first(HOME_MAX)
        end
      end

      # --- katalog platform -------------------------------------------------------------------------------------
      def self.source_for?(src) = src.present? && src.base_url.to_s.include?(HUB_HOST)
      def self.sources = ApiSource.enabled.ordered.to_a.select { |s| source_for?(s) && s.configured? }

      # { slug => Platform } untuk sebuah sumber; dari docs HTML (butuh token), cadangan berkas bawaan.
      def self.catalog(source = nil)
        Rails.cache.fetch([ "mola", "catalog", source&.id ], expires_in: 24.hours) do
          raw = (source && fetch_catalog(source)) || bundled_catalog
          raw.reject { |p| EXCLUDED.include?(p["slug"].to_s) }
             .to_h { |p| [ p["slug"].to_s, Platform.new(slug: p["slug"].to_s, name: p["name"].to_s, logo: p["logo"].to_s,
                                                       actions: Array(p["endpoints"]).to_h { |e| [ (e["action"] || e["path"].to_s.split("/").last).to_s, e ] }) ] }
        end
      end

      def self.bundled_catalog = JSON.parse(Rails.root.join("config/mola_platforms.json").read)

      def self.fetch_catalog(source)
        uri = URI.parse("#{source.base_url}/docs/dramabox?token=#{CGI.escape(source.api_key.to_s)}")
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) { |h| h.get(uri.request_uri, "User-Agent" => "DracinManager/1.0") }
        html = res.body.to_s
        i = html.index("ALL_PLATFORMS =") or return nil
        start = html.index("[", i) or return nil
        depth = 0
        j = start
        while j < html.length
          c = html[j]
          depth += 1 if c == "[" || c == "{"
          if c == "]" || c == "}"
            depth -= 1
            break if depth.zero?
          end
          j += 1
        end
        list = JSON.parse(html[start..j])
        list.is_a?(Array) && list.size > 10 ? list : nil
      rescue StandardError => e
        Rails.logger.warn("[Mola] katalog docs gagal (#{e.class}: #{e.message}) → pakai berkas bawaan")
        nil
      end

      # Entri platform untuk Provider.apply_status! (dipakai Client#status sumber Mola).
      def self.platform_entries(source)
        catalog(source).values.map do |p|
          { "id" => p.slug, "name" => p.name, "logo" => (p.logo.present? ? "#{source.base_url}#{p.logo}" : nil), "status" => "online",
            "adapter" => "mola", "enabled" => false, "category" => (CHINESE.include?(p.slug) ? "chinese_drama" : "short_drama") }
        end
      end

      # Adapter cadangan untuk provider non-Mola yang platformnya ada di hub Mola.
      def self.fallback_for(provider, lang: nil)
        return nil if provider.adapter_slug == "mola"
        src = sources.detect { |s| catalog(s).key?(provider.slug) }
        src && new(provider, lang: lang, source: src)
      end

      attr_reader :source

      def initialize(provider, api_key: nil, lang: nil, source: nil)
        @source = source || (provider.api_source if self.class.source_for?(provider.api_source)) || self.class.sources.first
        super(provider, api_key: @source&.api_key.presence || api_key, lang: lang)
      end

      def host
        @host ||= URI.parse(source&.base_url.presence || self.class.default_host).then { |u| "#{u.scheme}://#{u.host}" }
      end

      def platform
        @platform ||= self.class.catalog(source)[slug] or raise Unsupported, I18n.t("dracin_api.errors.unsupported", provider: provider.name)
      end

      # --- kontrak adapter --------------------------------------------------------------------------------------
      def home
        acts = platform.home_actions
        return [] if acts.empty?
        ensure_language!
        results = concurrently(*acts.map { |a| -> { list_items(call(a, page: 1, size: 20)) } })
        seen = []
        acts.zip(results).map do |a, items|
          title = section_title(a)
          title = a.titleize if seen.include?(title) # hot + rank sama-sama "Sedang Tren" → bedakan
          seen << title
          section(title, items)
        end
      end

      def search(q, page: 1)
        ensure_language!
        json = call("search", page: page, platform.keyword_param => q)
        items = list_items(json)
        page(items, page: page, has_more: more?(json, items.size, page))
      end

      def detail(id)
        ensure_language!
        json = call("detail", platform.id_param => id)
        h = drama_hash(json) || {}
        d = to_drama(h)
        d.id = id.to_s if d.id.blank?
        d.title = provider.name if d.title.blank?
        d
      end

      def episodes(id)
        act = platform.episodes_action or return []
        json = call(act, platform.id_param => id)
        list = find_list(json) { |h| EP_NUM_KEYS.any? { |k| h.key?(k) } || EP_ID_KEYS.any? { |k| h.key?(k) } } || []
        list.each_with_index.map do |e, i|
          n = pick(e, *EP_NUM_KEYS).to_s[/\d+/].to_i
          n = i + 1 if n.zero?
          locked = %w[isLocked is_locked locked].any? { |k| e[k] == true || e[k] == 1 }
          episode(number: n, title: pick(e, "title", "chapterName", "name", "episode_title").presence || "EP #{n}", locked: locked,
                  thumbnail: pick(e, "cover", "thumbnail", "thumb", "image"), payload: { "episode_id" => pick(e, *EP_ID_KEYS).to_s })
        end
      end

      def play(id, ep)
        act = platform.play_action or raise Unsupported, I18n.t("dracin_api.errors.unsupported", provider: provider.name)
        item = find_episode(id, ep)
        params = { platform.id_param => id, platform.episode_param => ep }
        # platform yang butuh id episode/chapter (mis. iqiyi tv_id, melolo vid) → diisi dari daftar episode bila ada paramnya
        extra = platform.params_of(act) - params.keys.map(&:to_s) - %w[lang token codec]
        extra.each { |n| params[n] = item&.payload.to_h["episode_id"].presence if n =~ /id|vid/i }
        json = call(act, **params.compact)
        d = unwrap(json)
        sources = stream_sources(d)
        raise Error, I18n.t("dracin_api.errors.http_error", code: "stream kosong") if sources.empty?
        best = sources.max_by { |s| s[:label][/\d+/].to_i }
        subs = Array(d["subtitles"]).filter_map do |s|
          next unless s.is_a?(Hash) && pick(s, "url", "subtitleUrl", "subtitle_url").present?
          subtitle(lang: pick(s, "lang", "language", "languageCode", "code"), url: pick(s, "url", "subtitleUrl", "subtitle_url"), label: pick(s, "label", "name", "language"))
        end
        stream(url: best[:url], episode: ep, sources: sources, subtitles: subs)
      end

      private
      # Token lewat header X-API-TOKEN; param lang hanya untuk aksi yang memang menerimanya.
      def call(action, size: nil, **params)
        raise MissingApiKey, I18n.t("dracin_api.errors.missing_api_key") unless api_key
        params[:lang] = lang if platform.lang?(action) && !params.key?(:lang)
        params[platform.size_param(action).to_sym] = size if size && platform.size_param(action)
        path = platform.actions.dig(action, "path").presence || "/api/#{slug}/#{action}"
        json = memo(path, params) { Http.get_json("#{host}#{path}", params: params, headers: { "X-API-TOKEN" => api_key }) }
        if json.is_a?(Hash) && json["success"] == false
          raise Error, [ json["message"], json["error"] ].compact_blank.join(" — ").presence || "Mola: #{action} gagal"
        end
        json
      end

      # Bahasa katalog bersifat stateful per token di gateway → cukup diset 1x/hari per platform.
      def ensure_language!
        return unless platform.action?("set_language")
        Rails.cache.fetch([ "mola", "lang", source&.id, slug, lang ], expires_in: 24.hours) do
          call("set_language", lang: lang) rescue nil
          true
        end
      end

      def section_title(action)
        key = SECTION_TITLES[action] || :default
        I18n.t("template.v1.sections.#{key}", default: action.titleize)
      end

      def more?(json, count, page)
        root = json.is_a?(Hash) ? (json["data"].is_a?(Hash) ? json["data"] : json) : {}
        return root["hasMore"] || root["has_more"] if root.key?("hasMore") || root.key?("has_more")
        return page.to_i < root["total_pages"].to_i if root["total_pages"].to_i.positive?
        count >= 10
      end

      # --- normalisasi -------------------------------------------------------------------------------------------
      def pick(h, *keys)
        return nil unless h.is_a?(Hash)
        keys.each { |k| v = h[k]; return v if v.present? && v != "<nil>" }
        nil
      end

      def unwrap(json)
        d = json
        d = d["data"] while d.is_a?(Hash) && d["data"].is_a?(Hash) && (d.keys - %w[data success message]).empty?
        d.is_a?(Hash) ? d : {}
      end

      # Array hash pertama (DFS) yang elemennya memenuhi blok (default: punya kunci judul).
      def find_list(obj, depth = 0, &pred)
        pred ||= ->(h) { TITLE_KEYS.any? { |k| h.key?(k) } }
        return nil if depth > 4
        if obj.is_a?(Array)
          return obj if obj.any? && obj.all? { |x| x.is_a?(Hash) } && obj.any? { |x| pred.call(x) }
        elsif obj.is_a?(Hash)
          %w[data books playlets list items results dramas episodes rows records].each do |k|
            found = find_list(obj[k], depth + 1, &pred) if obj.key?(k)
            return found if found
          end
          obj.each_value { |v| found = find_list(v, depth + 1, &pred) if v.is_a?(Array) || v.is_a?(Hash); return found if found }
        end
        nil
      end

      def list_items(json) = (find_list(json) || []).map { |h| to_drama(h) }

      def drama_hash(json)
        d = unwrap(json)
        return d if TITLE_KEYS.any? { |k| d.key?(k) }
        find_list(json)&.first
      end

      def to_drama(h)
        tags = h["tags"] || h["tag_names"] || h["genres"] || h["tagList"]
        genres = Array(tags).map { |t| t.is_a?(Hash) ? (t["name"] || t["title"]) : t }.map(&:to_s)
        genres << pick(h, "categoryName", "category_text", "category", "genre").to_s if genres.empty?
        drama(id: pick(h, *ID_KEYS), title: pick(h, *TITLE_KEYS), cover: pick(h, *COVER_KEYS), synopsis: pick(h, *DESC_KEYS),
              episodes: pick(h, *COUNT_KEYS).to_i.nonzero?, genres: genres.reject { |g| g.blank? || g == "<nil>" },
              language: nil, rating: nil, year: nil, status: pick(h, "status", "corner", "finish_status").presence&.to_s)
      end

      # [{label:, url:}] dari qualities/videos/streams/resolutions[] atau url tunggal.
      def stream_sources(d)
        list = %w[qualities videos streams resolutions sources urls].flat_map { |k| Array(d[k]) }.select { |s| s.is_a?(Hash) }
        srcs = list.filter_map do |s|
          url = pick(s, *URL_KEYS) or next
          { label: pick(s, "quality", "label", "resolution", "clarity", "name", "definition").to_s.presence || "Auto", url: url.to_s }
        end
        srcs = [ { label: pick(d, "clarity", "quality").to_s.presence || "Auto", url: pick(d, *URL_KEYS).to_s } ] if srcs.empty? && pick(d, *URL_KEYS).present?
        srcs.uniq { |s| s[:url] }
      end
    end
  end
end
