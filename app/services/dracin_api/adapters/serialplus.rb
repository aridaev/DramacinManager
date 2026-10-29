module DracinApi
  module Adapters
    # https://serealplus.goodbos.online (Serial+) — auth via query ?code=KEY
    #   /api/home?lang=&page=    → { data: { hasMore, list: [ { contentId, contentName, contentCoverUrl, chapterNum, tag } ] } }
    #   /api/latest?lang=        → { data: { records: [ { columnName, records: [ { contentId, contentName, url(=cover), tag } ] } ] } }
    #   /api/search?q=&lang=     → { data: { hasMore, list: [...] } }
    #   /api/detail?id=&lang=    → { data: { id, contentName, contentCoverUrl, introduce, chapterNum, classList, tagList, contentScore } }
    #   /api/episodes?id=&lang=  → { total, episodes: [ { seqNo, duration, lock, videoUrl } ] }
    # `lock` 1/2 adalah flag paywall aplikasi asli; videoUrl tetap valid (HEAD 200 video/mp4), jadi tidak dipakai memblokir.
    class Serialplus < Base
      default_host "https://serealplus.goodbos.online"

      def home
        latest, home = concurrently(-> { get("/api/latest", lang: lang) }, -> { get("/api/home", lang: lang, page: 1) })
        sections = Array(latest.dig("data", "records")).filter_map do |col|
          items = Array(col["records"]).map { |d| to_drama(d) }
          section(col["columnName"].to_s.strip.presence || I18n.t("template.v1.sections.latest"), items) if items.any?
        end
        sections << section(I18n.t("template.v1.sections.for_you"), Array(home.dig("data", "list")).map { |d| to_drama(d) })
      end

      def search(q, page: 1)
        data = get("/api/search", q: q, lang: lang, page: page)["data"] || {}
        page(Array(data["list"]).map { |d| to_drama(d) }, page: page, has_more: data["hasMore"] == true)
      end

      def detail(id)
        d = get("/api/detail", id: id, lang: lang)["data"] || {}
        drama(id: d["id"] || id, title: d["contentName"].to_s.strip, cover: d["contentCoverUrl"], synopsis: d["introduce"] || d["shortIntroduce"],
              episodes: d["chapterNum"].to_i.nonzero?, genres: (Array(d["classList"]).map { |c| c["name"] } + Array(d["tagList"]).map { |t| t.is_a?(Hash) ? t["name"] : t }).first(5),
              rating: d["contentScore"].presence, language: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(get("/api/episodes", id: id, lang: lang)["episodes"]).map do |ep|
          episode(number: ep["seqNo"], title: "EP #{ep['seqNo']}", thumbnail: nil, duration: seconds_to_clock(ep["duration"]),
                  locked: ep["videoUrl"].blank?, payload: ep.slice("videoUrl"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = item.payload["videoUrl"]
        return nil if url.blank?
        stream(url: url, episode: ep)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def to_drama(d)
        # /api/latest memakai `url` (bukan contentCoverUrl) untuk cover.
        cover = d["contentCoverUrl"].presence || (d["url"].to_s.match?(/\.(jpe?g|png|webp)(\?|$)/i) ? d["url"] : nil)
        drama(id: d["contentId"] || d["id"], title: d["contentName"].to_s.strip, cover: cover, synopsis: d["introduce"],
              episodes: (d["chapterNum"] || d["chapterNumber"]).to_i.nonzero?, genres: Array(d["tag"].is_a?(String) ? d["tag"].split(/[,，]/) : d["tag"]).first(5),
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
