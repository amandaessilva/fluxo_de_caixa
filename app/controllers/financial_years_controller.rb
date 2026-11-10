class FinancialYearsController < ApplicationController
  def create
    balance = params[:opening_balance].present? ? money_param(params[:opening_balance]) : nil
    year = YearBuilder.call(params[:year], opening_balance: balance)
    session[:year] = year.year
    redirect_to root_path(year: year.year), notice: 'Ano disponível, com limites e contas fixas previstos.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to settings_path, alert: e.message
  end
end
