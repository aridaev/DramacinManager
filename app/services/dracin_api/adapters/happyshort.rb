module DracinApi
  module Adapters
    # https://happyshort.goodbos.online — token lewat query ?code= (endpoint dipakai frontend "Tonton")
    #   /api/hs/home?page=&size=&lang=  → { dramas: [d], has_next, total_pages }
    #   /api/hs/search?q=&lang=         → { dramas: [d] }
    #   /api/hs/detail?id=              → { episode_num, video: d }
    #   /api/hs/episodes?id=            → { episodes: [ { id, order, name, lock } ], total }
    #   /api/hs/play?id=&ep=<episode id> → { url, cdn_url, episode: { order, m3u8_link } }
    #   d = { id, name, cover, big_cover, introduce, episode_num, is_end }
    class Happyshort < Base
      default_host "https://happyshort.goodbos.online"
      SIZE = 24

      def home
        data = get("/api/hs/home", page: 1, size: SIZE, lang: lang)
        [ section(I18n.t("template.v1.sections.for_you"), Array(data["dramas"]).map { |d| to_drama(d) }) ]
      end

      def search(q, page: 1)
        return page([], page: page, has_more: false) if page.to_i > 1
        data = get("/api/hs/search", q: q, lang: lang)
        page(Array(data["dramas"]).map { |d| to_drama(d) }, page: page, has_more: false)
      end

      def detail(id)
        d = get("/api/hs/detail", id: id, lang: lang)
        v = d["video"].is_a?(Hash) ? d["video"] : d
        to_drama(v.merge("episode_num" => d["episode_num"] || v["episode_num"]), id)
      end

      def episodes(id)
        Array(get("/api/hs/episodes", id: id, lang: lang)["episodes"]).map do |e|
          num = e["order"].to_i
          episode(number: num, title: "EP #{num}", thumbnail: nil, duration: nil, locked: false, payload: { "eid" => e["id"] })
        end.select { |e| e.number.positive? }.sort_by(&:number)
      end

      def play(id, ep)
        e = find_episode(id, ep) or return nil
        v = get("/api/hs/play", id: id, ep: e.payload["eid"], lang: lang)
        return nil if v["episode"].is_a?(Hash) && v["episode"]["order"].to_i != ep.to_i
        url = v["url"].presence || v["cdn_url"].presence
        return nil if url.blank?
        sources = [ { label: "Auto", url: url } ]
        sources << { label: "CDN", url: v["cdn_url"] } if v["cdn_url"].present? && v["cdn_url"] != url
        stream(url: url, episode: ep, sources: sources, format: "MP4")
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def to_drama(d, fallback_id = nil)
        drama(id: d["id"] || d["video_id"] || fallback_id, title: d["name"] || d["video_name"] || d["title"], cover: d["cover"].presence || d["big_cover"],
              synopsis: d["introduce"].presence, episodes: d["episode_num"].to_i.nonzero?, language: nil, rating: nil, year: nil,
              status: d["is_end"].to_i == 1 ? I18n.t("template.v1.status.completed", default: "Completed") : nil)
      end
    end
  end
end
