module DracinApi
  module Adapters
    # https://netshort.goodbos.online — header x-token
    #   /api/home/:page?lang=   → { data: { contentName, contentInfos: [ { shortPlayId, shortPlayName, shortPlayCover, labelArray } ] } }
    #   /api/list/:page?lang=   → { data: { dataList: [...], completed } }
    #   /api/search?q=&lang=    → { data: { searchCodeSearchResult: [ { shortPlayId, shortPlayName (dengan <em>), shortPlayCover, labelNameList } ] } }
    #   /api/drama/:id?lang=    → { data: { shortPlayName, shortPlayCover, totalEpisode, shortPlayEpisodeList: [ { episodeNo, isLock, playVoucher, episodeCover, subtitleList } ] } }
    class Netshort < Base
      default_host "https://netshort.goodbos.online"
      LANG_MAP = { "id" => "in" }.freeze

      def home
        home = get("/api/home/1", lang: lang)["data"] || {}
        list = get("/api/list/1", lang: lang)["data"] || {}
        [
          section(home["contentName"].presence || I18n.t("template.v1.sections.for_you"), Array(home["contentInfos"]).map { |d| to_drama(d) }),
          section(I18n.t("template.v1.sections.trending"), Array(list["dataList"]).map { |d| to_drama(d) })
        ]
      end

      def search(q, page: 1)
        data = get("/api/search", q: q, lang: lang)["data"] || {}
        page(Array(data["searchCodeSearchResult"]).map { |d| to_drama(d) }, page: 1, has_more: false)
      end

      def detail(id)
        d = drama_data(id)
        drama(id: d["shortPlayId"] || id, title: d["shortPlayName"], cover: d["shortPlayCover"], synopsis: d["shortPlayIntroduction"] || d["introduction"],
              episodes: d["totalEpisode"].to_i.nonzero?, genres: labels(d), language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(drama_data(id)["shortPlayEpisodeList"]).map do |e|
          episode(number: e["episodeNo"], title: "EP #{e['episodeNo']}", thumbnail: e["episodeCover"], duration: nil,
                  locked: e["isLock"] == true, payload: e.slice("playVoucher", "subtitleList"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = item.payload["playVoucher"]
        return nil if url.blank?
        subs = Array(item.payload["subtitleList"]).map { |s| subtitle(lang: s["language"], label: s["languageName"] || s["language"], url: s["subtitleUrl"] || s["url"]) }.select { |s| s[:url].present? }
        stream(url: url, episode: ep, subtitles: subs)
      end

      private
      def drama_data(id) = get("/api/drama/#{id}", lang: lang)["data"] || {}

      def labels(d)
        tags = d["labelArray"] || d["labelNameList"]
        tags = d["labelNames"].to_s.split(",") if tags.blank? && d["labelNames"].present?
        Array(tags).first(5)
      end

      def to_drama(d)
        drama(id: d["shortPlayId"], title: ActionController::Base.helpers.strip_tags(d["shortPlayName"].to_s), cover: d["shortPlayCover"],
              synopsis: d["shortPlayIntroduction"], genres: labels(d), episodes: d["totalEpisode"].to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
