# Kelola penonton (member) & pengajuan deposit per instance: approve/tolak, perpanjang, cabut bebas iklan,
# plus statistik deposit (grafik per hari, per paket) dengan filter periode/status/paket/username.
# Akses mengikuti Admin::InstancesController (admin semua instance, user hanya miliknya).
class Admin::MembersController < ApplicationController
  layout "application"
  before_action :load_instance

  PERIODS = [ 7, 30, 90, 365 ].freeze

  def index
    load_filters
    reqs = @instance.deposit_requests.includes(:member)
    @pending = reqs.pending.order(created_at: :asc)

    now = Time.current
    @stat_members      = @instance.members.count
    @stat_adfree       = @instance.members.where("adfree_until > ?", now).count
    @stat_approved_all = @instance.deposit_requests.approved.count
    @stat_revenue_all  = @instance.deposit_requests.approved.sum(:amount_value)

    approved_in = @instance.deposit_requests.approved.where(reviewed_at: @from..@to)
    @stat_approved    = approved_in.count
    @stat_revenue     = approved_in.sum(:amount_value)
    @stat_rejected    = @instance.deposit_requests.rejected.where(reviewed_at: @from..@to).count
    @stat_new_members = @instance.members.where(created_at: @from..@to).count

    days = ((@to.to_date - @from.to_date).to_i + 1).clamp(1, 366)
    @series = Array.new(days) { |i| [ @from.to_date + i, 0, 0 ] }
    index_of = @series.each_with_index.to_h { |(d, _, _), i| [ d, i ] }
    approved_in.pluck(:reviewed_at, :amount_value).each do |t, v|
      i = index_of[t.in_time_zone.to_date] or next
      @series[i][1] += 1; @series[i][2] += v.to_i
    end
    @reg_series = Array.new(days) { |i| [ @from.to_date + i, 0 ] }
    @instance.members.where(created_at: @from..@to).pluck(:created_at).each do |t|
      i = index_of[t.in_time_zone.to_date] and @reg_series[i][1] += 1
    end
    @by_package = approved_in.group(:days).pluck(:days, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount_value),0)")).sort_by { |d, _, _| d.to_i }

    hist = reqs
    hist = hist.where(status: @status) if @status
    hist = hist.where(days: @pkg) if @pkg
    hist = hist.joins(:member).where("members.username LIKE ?", "%#{Member.sanitize_sql_like(@q)}%") if @q.present?
    hist = hist.where("COALESCE(deposit_requests.reviewed_at, deposit_requests.created_at) BETWEEN ? AND ?", @from, @to)
    @history_count = hist.count
    @history = hist.order(created_at: :desc).limit(300)

    mem = @instance.members
    mem = mem.where("username LIKE ?", "%#{Member.sanitize_sql_like(@q)}%") if @q.present?
    case @mstatus
    when "adfree"  then mem = mem.where("adfree_until > ?", now)
    when "expired" then mem = mem.where("adfree_until <= ?", now)
    when "none"    then mem = mem.where(adfree_until: nil)
    end
    @members_count = mem.count
    @members = mem.ordered.includes(:deposit_requests).limit(300)
    @package_options = (@instance.adfree_packages.map { |p| p["days"] } + @instance.deposit_requests.distinct.pluck(:days)).compact.uniq.sort
  end

  def approve
    req = @instance.deposit_requests.pending.find(params[:id])
    req.approve!(params[:days])
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.approved", name: req.member.username, days: req.days, until: l(req.adfree_until, format: :full))
  end

  def reject
    req = @instance.deposit_requests.pending.find(params[:id])
    req.reject!
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.rejected", name: req.member.username)
  end

  def grant
    m = @instance.members.find(params[:id])
    days = params[:days].to_i.clamp(1, 3650)
    m.grant_adfree!(days)
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.granted", name: m.username, days: days, until: l(m.adfree_until, format: :full))
  end

  def revoke
    m = @instance.members.find(params[:id])
    m.revoke_adfree!
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.revoked", name: m.username)
  end

  def destroy
    m = @instance.members.find(params[:id])
    m.destroy
    redirect_to admin_instance_members_path(@instance), notice: t("admin.members.deleted", name: m.username)
  end

  private
  def load_instance
    scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)
    @instance = scope.find(params[:instance_id])
  end

  def load_filters
    @period  = PERIODS.include?(params[:period].to_i) ? params[:period].to_i : 30
    from_p   = parse_date(params[:from]); to_p = parse_date(params[:to])
    @custom  = from_p.present? || to_p.present?
    @from    = (from_p || (to_p ? to_p - (@period - 1).days : (@period - 1).days.ago.to_date)).beginning_of_day
    @to      = (to_p || Time.current.to_date).end_of_day
    @from, @to = @to.beginning_of_day, @from.end_of_day if @from > @to
    @from    = (@to.to_date - 365).beginning_of_day if (@to.to_date - @from.to_date) > 365
    @status  = %w[pending approved rejected].include?(params[:status]) ? params[:status] : nil
    @q       = params[:q].to_s.strip.downcase.first(30)
    @pkg     = params[:pkg].to_i if params[:pkg].to_s.match?(/\A\d+\z/)
    @mstatus = %w[adfree expired none].include?(params[:mstatus]) ? params[:mstatus] : nil
  end

  def parse_date(s)
    s.present? ? Date.iso8601(s.to_s) : nil
  rescue ArgumentError
    nil
  end
end
