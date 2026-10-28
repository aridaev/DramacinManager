module DracinApi
  module Adapters
    # https://flextv.goodbos.online — auth ?code=KEY
    #   /api/drama/home|popular|newest?lang=&page=   → { data: { dramas: [ { series_id, name, cover, description, tags, serial_status } ] } }
    #   /api/drama/search?q=&lang=                   → { data: { dramas: [...] } }
    #   /api/drama/detail?series_id=&lang=           → { data: { detail: { series_id, series_name, cover, description, total_episodes?, tags } } }
    #   /api/allepisodes?id=&lang=                   → { data: { episodes: [ { no, duration, video_url (HLS abr), title, subtitle: [], unlocked } ], total } }
    # Catatan: DracinAPI hanya membuka 5–7 episode pertama per judul (total dari API, bukan batasan kode ini).
    class Flextv < Base
      default_host "https://flextv.goodbos.online"

      def home
        home, popular, newest = concurrently(-> { list("/api/drama/home") }, -> { list("/api/drama/popular", page: 1) }, -> { list("/api/drama/newest", page: 1) })
        [
          section(I18n.t("template.v1.sections.for_you"), home),
          section(I18n.t("template.v1.sections.trending"), popular),
          section(I18n.t("template.v1.sections.latest"), newest)
        ]
      end

      def search(q, page: 1)
        page(list("/api/drama/search", keyword: q), page: 1, has_more: false)
      end

      def detail(id)
        d = get("/api/drama/detail", series_id: id, lang: lang).dig("data", "detail") || {}
        drama(id: d["series_id"] || id, title: (d["series_name"] || d["name"]).to_s.strip, cover: d["cover"], synopsis: d["description"],
              genres: Array(d["tags"]).map { |t| t.is_a?(Hash) ? t["name"] : t }.first(5),
              episodes: (d["total_episodes"] || d["episode_count"] || d["total"]).to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(get("/api/allepisodes", id: id, lang: lang).dig("data", "episodes")).map do |e|
          episode(number: e["no"], title: e["title"].presence || "EP #{e['no']}", thumbnail: nil, duration: seconds_to_clock(e["duration"]),
                  locked: e["video_url"].blank?, payload: e.slice("video_url", "subtitle"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = item.payload["video_url"]
        return nil if url.blank?
        subs = Array(item.payload["subtitle"]).filter_map { |s| s.is_a?(Hash) && (s["url"] || s["src"]).present? ? subtitle(lang: s["lang"] || s["language"], label: s["name"] || s["label"], url: s["url"] || s["src"]) : nil }
        stream(url: url, episode: ep, subtitles: subs)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def list(path, **params) = Array(get(path, params.merge(lang: lang)).dig("data", "dramas")).map { |d| to_drama(d) }

      def to_drama(d)
        drama(id: d["series_id"], title: (d["name"] || d["series_name"]).to_s.strip, cover: d["cover"], synopsis: d["description"],
              genres: Array(d["tags"]).map { |t| t.is_a?(Hash) ? t["name"] : t }.first(5), episodes: (d["total_episodes"] || d["episode_count"]).to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
