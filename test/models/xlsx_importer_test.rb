require 'test_helper'
class XlsxImporterTest < ActiveSupport::TestCase
  setup { setup_finances }
  teardown { @file&.close! }
  test 'cada coluna financeira gera um lançamento e K não gera duplicatas' do
    @file = workbook
    data = preview(@file)
    assert_empty data['unparsed']
    assert_equal 6, data['entries'].size
    assert_equal 4, data['entries'].count { |e| e['status'] == 'actual' }
    assert_equal 2, data['entries'].count { |e| e['status'] == 'planned' }
    assert_equal %w[benefit_received benefit_used expense income], data['entries'].select { |e| e['status'] == 'actual' }.map { |e| e['kind'] }.sort
    assert_equal 1, data['inferred_dates']
    assert data['entries'].first(4).all? { |e| e['date'] == '2026-01-15' }
    assert_equal 'Pix', data['entries'].first['payment_method']
    assert_match 'Juros', data['entries'].first['notes']
    year = XlsxImporter.commit!(data)
    assert_equal 6, year.entries.count
    assert_equal BigDecimal('200'), BalanceReport.new(year).closing_balance
    assert_equal BigDecimal('165'), BalanceReport.new(year, status: 'planned').closing_balance
    assert_equal data['summary'], XlsxImporter.summary(year.entries.map { |e| { 'date' => e.date.iso8601, 'status' => e.status, 'kind' => e.kind, 'amount' => e.amount.to_s('F') } })
  end
  test 'preserva limites diferentes entre meses e relata auxiliares' do
    @file = workbook(months: ['Janeiro', 'Fevereiro'], auxiliary: true)
    data = preview(@file)
    assert_equal ['200.0', '201.0'], data['limits'].map { |l| l['amount'] }
    assert_equal 'Parcelas', data['auxiliary'].first['sheet']
    assert_equal 1, data['auxiliary'].first['formula_cells']
    assert_equal 12, data['entries'].size
  end
  test 'sem confirmação não substitui registros existentes' do
    existing = entry
    @file = workbook
    data = preview(@file)
    assert_raises(XlsxImporter::InvalidFile) { XlsxImporter.commit!(data) }
    assert existing.reload
    assert_equal 1, Entry.count
  end
  test 'substitui somente o ano importado' do
    entry
    other = FinancialYear.create!(year: 2025)
    other.entries.create!(category: @category, date: '2025-01-01', description: 'Preservar', kind: 'income', status: 'actual', amount: 1)
    @file = workbook
    XlsxImporter.commit!(preview(@file), replace: true)
    assert_equal 1, other.entries.count
    assert_equal 6, @year.entries.count
  end
  test 'valores inválidos bloqueiam importação sem gravação parcial' do
    @file = workbook(invalid: true)
    data = preview(@file)
    assert data['unparsed'].any?
    assert_no_difference(['Entry.count', 'Category.count', 'MonthlyLimit.count']) do
      assert_raises(XlsxImporter::InvalidFile) { XlsxImporter.commit!(data) }
    end
  end
  test 'falha depois de apagar dados reverte toda transação' do
    existing = entry
    @file = workbook
    data = preview(@file)
    data['entries'].last['description'] = ''
    assert_raises(ActiveRecord::RecordInvalid) { XlsxImporter.commit!(data, replace: true) }
    assert_equal [existing.id], @year.entries.pluck(:id)
    assert_equal 0, MonthlyLimit.count
  end
  test 'conferência divergente reverte dados' do
    @file = workbook
    data = preview(@file)
    data['summary'].values.first['total'] = '999'
    assert_no_difference('Entry.count') do
      assert_raises(XlsxImporter::InvalidFile) { XlsxImporter.commit!(data) }
    end
  end
  test 'prévia desatualizada não sobrescreve alteração recente' do
    @file = workbook
    data = preview(@file)
    entry
    assert_raises(XlsxImporter::InvalidFile) { XlsxImporter.commit!(data, replace: true) }
  end
  test 'valida extensão e estrutura' do
    @file = workbook
    assert_raises(XlsxImporter::InvalidFile) { XlsxImporter.new(@file.path, filename: 'bad.csv', fallback_year: 2026).preview }
    @file.rewind; @file.truncate(0); @file.write('invalido'); @file.flush
    assert_raises(XlsxImporter::InvalidFile) { preview(@file) }
  end
  test 'ano identificado prevalece sobre ano informado' do
    @file = workbook(year: 2027)
    assert_equal 2027, preview(@file)['year']
  end
end
