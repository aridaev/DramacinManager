module DracinApi
  module Adapters
    # https://moboreels.goodbos.online — token lewat query ?code=
    #   /api/v1/series            → { data: { seriesList: [ { seriesId, seriesName, coverUrl, types, summary } ] } }
    #   /api/v1/search?q=         → { data: { mainData: { rows: [...] } } }
    #   /api/v1/series/:id        → { data: { episodes: [ { episNum, mediaUrl, coverUrl, duration, isLock, resolution, subtitles } ], totalEpisodes } }
    class Moboreels < Base
      default_host "https://moboreels.goodbos.online"

      def home
        list = series_list.map { |d| to_drama(d) }
        [ section(I18n.t("template.v1.sections.for_you"), list) ]
      end

      def search(q, page: 1)
        data = get("/api/v1/search", q: q)
        rows = Array(data.dig("data", "mainData", "rows")) + Array(data.dig("data", "subtitlesData", "rows"))
        page(rows.map { |d| to_drama(d) }, page: 1, has_more: false)
      end

      def detail(id)
        from_list = series_list.find { |d| d["seriesId"].to_s == id.to_s }
        data = series_data(id)
        base = from_list ? to_drama(from_list) : drama(id: id, title: data["seriesName"].presence || "##{id}")
        base.id = id.to_s
        base.cover ||= Array(data["episodes"]).first&.dig("coverUrl")
        base.episodes ||= data["totalEpisodes"].to_i.nonzero?
        base
      end

      def episodes(id)
        Array(series_data(id)["episodes"]).map do |e|
          episode(number: e["episNum"], title: "EP #{e['episNum']}", thumbnail: e["coverUrl"], duration: seconds_to_clock(e["duration"]),
                  locked: e["isLock"] == true, payload: e.slice("mediaUrl", "resolution", "subtitles"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = item.payload["mediaUrl"]
        return nil if url.blank?
        subs = Array(item.payload["subtitles"]).filter_map do |s|
          next unless s.is_a?(Hash)
          u = s["url"] || s["subtitleUrl"] || s["src"]
          subtitle(lang: s["lang"] || s["language"] || s["code"], label: s["name"] || s["label"], url: u) if u.present?
        end
        stream(url: url, episode: ep, quality: [ item.payload["resolution"].presence && "#{item.payload['resolution']}p" ].compact, subtitles: subs)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def series_data(id) = get("/api/v1/series/#{id}")["data"] || {}

      # Daftar seri dipakai home + detail (satu panggilan ~100 item), di-cache terpisah agar detail tidak mengulang.
      def series_list
        Rails.cache.fetch([ "dracin_api", "moboreels", "series_list" ], expires_in: 30.minutes) do
          Array(get("/api/v1/series")&.dig("data", "seriesList"))
        end
      end

      def to_drama(d)
        drama(id: d["seriesId"] || d["id"], title: d["seriesName"] || d["name"] || d["title"], cover: d["coverUrl"] || d["cover"],
              synopsis: d["summary"] || d["description"], genres: Array(d["types"]).first(5), episodes: d["totalEpisodes"].to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
