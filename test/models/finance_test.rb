require 'test_helper'
class FinanceTest < ActiveSupport::TestCase
  setup { setup_finances }
  test 'saldo inclui as quatro colunas e mantém situações separadas' do
    entry(kind: 'income', amount: '200.25')
    entry(kind: 'benefit_received', amount: '40.00')
    entry(kind: 'benefit_used', amount: '10.10')
    entry(kind: 'expense', amount: '30.15')
    entry(kind: 'expense', amount: '99.00', status: 'planned')
    actual = BalanceReport.new(@year, month: 1)
    assert_equal BigDecimal('300.00'), actual.closing_balance
    assert_equal BigDecimal('1.00'), BalanceReport.new(@year, month: 1, status: 'planned').closing_balance
    assert_equal BigDecimal('300.00'), BalanceReport.new(@year, month: 2).opening_balance
  end
  test 'limites por grupo somam despesas e benefícios usados' do
    limit = @year.monthly_limits.create!(category: @category, month: 1, amount: '25')
    entry(amount: '20')
    entry(kind: 'benefit_used', amount: '10')
    entry(kind: 'income', amount: '500')
    entry(status: 'planned', amount: '70')
    assert_equal BigDecimal('30'), BalanceReport.new(@year, month: 1).spending_by_category[@category.id]
    assert_equal BigDecimal('25'), limit.amount
  end
  test 'validações impedem valores e datas inválidos' do
    e = entry
    %w[0 -1].each { |amount| e.amount = amount; assert_not e.valid? }
    e.amount = 1
    e.kind = 'invalid'; assert_not e.valid?
    e.kind = 'income'; e.status = 'invalid'; assert_not e.valid?
    e.status = 'actual'; e.date = Date.new(2027,1,1); assert_not e.valid?
    e.date = nil; assert_not e.valid?
  end
  test 'ano seguinte herda limites por mês e apenas contas fixas' do
    @year.monthly_limits.create!(category: @category, month: 1, amount: 100)
    @year.monthly_limits.create!(category: @category, month: 2, amount: 120)
    entry(description: 'Evento isolado')
    rule = RecurringRule.create!(category: @category, description: 'Internet', kind: 'expense', amount: '80', day: 31, starts_on: '2026-11-01')
    following = YearBuilder.call(2027)
    assert_equal [BigDecimal('100'), BigDecimal('120')], following.monthly_limits.order(:month).pluck(:amount)
    assert_equal 12, following.entries.count
    assert following.entries.all? { |e| e.status == 'planned' && e.description == 'Internet' }
    assert_equal Date.new(2027,2,28), following.entries.order(:date).second.date
    assert_equal BigDecimal('90'), following.initial_balance('actual')
    assert_no_difference('Entry.count') { YearBuilder.call(2027); rule.materialize!(following) }
  end
  test 'parcelas atravessam anos mantendo total exato e dia base' do
    items = InstallmentBuilder.call({ date: '2026-11-30', description: 'Compra', category_id: @category.id, kind: 'expense', amount: '100.01', status: 'actual' }, count: 10)
    assert_equal 10, items.size
    assert_equal 8, FinancialYear.find_by!(year: 2027).entries.count
    assert_equal BigDecimal('100.01'), items.sum(&:amount)
    assert_equal Date.new(2027,2,28), items[3].date
    assert_equal Date.new(2027,3,30), items[4].date
    assert items.all? { |e| e.status == 'planned' }
  end
  test 'erro nas parcelas desfaz anos e lançamentos' do
    assert_no_difference(['FinancialYear.count', 'Entry.count']) do
      assert_raises(ArgumentError) do
        InstallmentBuilder.call({ date: '2026-12-15', description: '', category_id: @category.id, kind: 'expense', amount: '100' }, count: 10)
      end
    end
  end
  test 'vínculos entre anos não permitem ciclos' do
    following = YearBuilder.call(2027)
    @year.previous_year = following
    assert_not @year.valid?
  end
end
