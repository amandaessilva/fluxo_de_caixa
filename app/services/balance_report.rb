# Um relatório nunca combina valores planejados e realizados.
class BalanceReport
  attr_reader :financial_year, :status, :month
  def initialize(financial_year, status: 'actual', month: nil)
    raise ArgumentError, 'Situação inválida' unless Entry::STATUSES.key?(status)
    @financial_year, @status, @month = financial_year, status, month
    @entries = financial_year.entries.where(status: status)
  end

  def totals
    @totals ||= sum_by(month ? @entries.in_month(financial_year.year, month) : @entries, :kind)
  end

  def total(kind) = totals.fetch(kind, BigDecimal('0'))
  def variation = total('income') + total('benefit_received') - total('benefit_used') - total('expense')
  def opening_balance
    initial = financial_year.initial_balance(status)
    return initial unless month
    before = sum_by(@entries.where('date < ?', Date.new(financial_year.year, month)), :kind)
    initial + before.fetch('income', 0) + before.fetch('benefit_received', 0) - before.fetch('benefit_used', 0) - before.fetch('expense', 0)
  end
  def closing_balance = opening_balance + variation

  def spending_by_category
    relation = month ? @entries.in_month(financial_year.year, month) : @entries
    sum_by(relation.outgoing, :category_id)
  end
  private
  # SQLite usa afinidade numérica para DECIMAL. Somamos os atributos tipados
  # pelo Active Record em BigDecimal, evitando o SUM em ponto flutuante do SQLite.
  def sum_by(relation, key)
    relation.pluck(key, :amount).each_with_object(Hash.new { |h, k| h[k] = BigDecimal('0') }) do |(group, amount), result|
      result[group] += amount
    end
  end
end
