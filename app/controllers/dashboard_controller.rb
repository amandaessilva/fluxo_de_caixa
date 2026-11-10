class DashboardController < ApplicationController
  before_action :require_year
  def show
    @report = BalanceReport.new(selected_year, status: selected_status, month: selected_month)
    @entries = selected_year.entries.in_month(selected_year.year, selected_month).where(status: selected_status).includes(:category).order(:date, :id)
    @limits = selected_year.monthly_limits.where(month: selected_month).includes(:category)
  end
  def annual
    @reports = Entry::STATUSES.keys.to_h { |status| [status, (1..12).map { |month| BalanceReport.new(selected_year, status: status, month: month) }] }
  end
end
