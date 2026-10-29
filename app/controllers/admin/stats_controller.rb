# Statistik pengunjung situs publik per instance: tampilan/pengunjung unik per hari, negara, perangkat, OS,
# browser, halaman & drama terpopuler, sumber rujukan. Akses mengikuti Admin::MembersController.
class Admin::StatsController < ApplicationController
  layout "application"
  before_action :load_instance

  PERIODS = [ 7, 30, 90 ].freeze

  def index
    @period = PERIODS.include?(params[:period].to_i) ? params[:period].to_i : 7
    @from = (@period - 1).days.ago.beginning_of_day
    @to   = Time.current.end_of_day
    @include_bots = params[:bots] == "1"
    base = @instance.visits.where(created_at: @from..@to)
    base = base.humans unless @include_bots
    @scope = base

    @views    = base.count
    @visitors = base.distinct.count(:visitor_id)
    @today    = base.where(created_at: Time.current.all_day)
    @views_today = @today.count
    @visitors_today = @today.distinct.count(:visitor_id)
    @bots = @instance.visits.where(created_at: @from..@to, device: "bot").count

    days = @period
    tz = Time.zone.tzinfo.name
    by_day = base.group(Arel.sql("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE #{Visit.connection.quote(tz)})"))
    views_by_day    = by_day.count
    visitors_by_day = by_day.distinct.count(:visitor_id)
    @series = Array.new(days) { |i| d = @from.to_date + i; [ d, views_by_day[d].to_i, visitors_by_day[d].to_i ] }

    @by_country = top(base, :country, 12)
    @by_device  = top(base, :device, 5)
    @by_os      = top(base, :os, 8)
    @by_browser = top(base, :browser, 8)
    @by_kind    = top(base, :kind, 8)
    @by_ref     = top(base.where.not(referrer_host: nil), :referrer_host, 10)
    @by_path    = top(base, :path, 15)
    @by_drama   = base.where(kind: %w[drama watch]).where.not(drama_id: nil).group(:provider, :drama_id).count.sort_by { |_, c| -c }.first(10)
    @by_hour    = base.group(Arel.sql("EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC' AT TIME ZONE #{Visit.connection.quote(tz)})::int")).count
    @recent     = base.order(created_at: :desc).limit(40)
  end

  private
  def load_instance
    scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)
    @instance = scope.find(params[:instance_id])
  end

  def top(scope, col, n)
    scope.group(col).count.sort_by { |_, c| -c }.first(n)
  end
end
