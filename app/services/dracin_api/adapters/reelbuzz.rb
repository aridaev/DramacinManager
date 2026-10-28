module DracinApi
  module Adapters
    # https://reelbuzz.goodbos.online — token lewat query ?code=
    #   /api/dramas?offset=        → { dramas: [ { drama_id, name, cover_url, episodes, description } ], hasMore, offset, total }
    #   /api/search?q=             → { results: [...], total }
    #   /api/drama/detail?id=      → { rows: { id, name, coverUrl, description, episodes, tagList: [ { name } ],
    #                                  episodeList: [ { episodeNo, coverUrl, charge, paid, qualityList: [ { quality, url } ], fileUrl, webVtt } ] } }
    class Reelbuzz < Base
      default_host "https://reelbuzz.goodbos.online"
      PER_PAGE = 18

      def home
        data = get("/api/dramas", offset: 0)
        [ section(I18n.t("template.v1.sections.latest"), Array(data["dramas"]).map { |d| to_drama(d) }) ]
      end

      def search(q, page: 1)
        data = get("/api/search", q: q)
        page(Array(data["results"]).map { |d| to_drama(d) }, page: 1, has_more: false)
      end

      def detail(id)
        d = detail_data(id)
        drama(id: d["id"] || id, title: d["name"], cover: d["coverUrl"], synopsis: d["description"], episodes: (d["episodes"] || d["maxEpisodeNo"]).to_i.nonzero?,
              genres: Array(d["tagList"]).map { |t| t["name"] }.first(5), language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(detail_data(id)["episodeList"]).map do |e|
          episode(number: e["episodeNo"], title: "EP #{e['episodeNo']}", thumbnail: e["coverUrl"], duration: nil,
                  locked: false, payload: e.slice("qualityList", "fileUrl", "webVtt"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        qualities = Array(item.payload["qualityList"]).select { |q| q["url"].present? }
        best = qualities.max_by { |q| q["quality"].to_s.to_i } || {}
        url = best["url"].presence || item.payload["fileUrl"]
        return nil if url.blank?
        subs = item.payload["webVtt"].present? ? [ subtitle(lang: lang, label: "Subtitle", url: item.payload["webVtt"]) ] : []
        sources = qualities.sort_by { |q| -q["quality"].to_s.to_i }.map { |q| { label: "#{q['quality'].to_s.to_i}p", url: q["url"] } }
        stream(url: url, episode: ep, sources: sources, subtitles: subs)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def detail_data(id) = get("/api/drama/detail", id: id)["rows"] || {}

      def to_drama(d)
        drama(id: d["drama_id"] || d["id"], title: d["name"], cover: d["cover_url"] || d["coverUrl"], synopsis: d["description"],
              episodes: d["episodes"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
