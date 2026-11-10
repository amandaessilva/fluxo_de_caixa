require 'test_helper'

# O layout replica apenas cabeçalhos/posições; todos os valores são sintéticos.
class ReferenceLayoutTest < ActiveSupport::TestCase
  setup { setup_finances }
  teardown { @file&.close! }

  def reference_workbook
    @file = Tempfile.new(['reference-layout', '.xlsx'])
    Axlsx::Package.new do |package|
      package.workbook.add_worksheet(name: 'Janeiro') do |sheet|
        (1..212).each do |row|
          cells = case row
          when 3 then ['REALIZADO']
          when 4 then ['Data', 'Descrição', 'Tipo Lançamento', 'Grupo', 'obs', 'tx juros a.m', 'ENTRADA', 'ent vale', 'said vale', 'SAIDA', 'ACUMULADO']
          when 5 then [nil, 'Saldo anterior', nil, nil, nil, nil, 20]
          when 6 then [Date.new(2026,1,7), 'Movimento sintético', 'Pix', 'Grupo sintético', nil, nil, 10, 4, 2, 3, '=K5+(G6-J6)', nil, 'Grupo sintético', 90]
          when 127 then [nil, 'TOTAL', nil, nil, nil, nil, '=SUM(G5:G126)']
          when 129 then ['PREVISTO']
          when 130 then ['DATA', 'DESCRIÇÃO', 'Tipo de pagamento', 'GRUPO', 'obs', nil, 'ENTRADA', nil, nil, 'SAÍDA', 'ACUMULADO']
          when 131 then [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, '=K127']
          when 132 then [nil, 'Previsão sintética', nil, 'Grupo sintético', nil, nil, nil, 8, 1, 6]
          when 212 then [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, '=K211']
          else []
          end
          cells[22] = 9 if row == 132
          sheet.add_row(cells, escape_formulas: false)
        end
      end
      package.workbook.add_worksheet(name: 'RESUMO ANUAL') do |sheet|
        52.times { sheet.add_row ['Resumo'] }
        sheet.add_row [Date.new(2012,2,3), 'Receita antiga sintética', nil, 'Outro grupo', nil, nil, 11]
      end
      package.workbook.add_worksheet(name: 'Plan1') do |sheet|
        sheet.add_row ['Receitas', 'Despesas', 'Contas Fixas', 'Parcelas']
      end
      package.serialize(@file.path)
    end
    @file
  end

  test 'layout com vales e cabeçalho previsto sem H I importa todas as colunas' do
    file = reference_workbook
    data = XlsxImporter.new(file.path, filename: 'referencia.xlsx', fallback_year: 2027, force_year: true).preview
    assert_empty data['unparsed']
    assert_equal 2027, data['year']
    assert_equal 7, data['entries'].size
    assert_equal 4, data['entries'].count { |e| e['status'] == 'actual' }
    assert_equal 3, data['entries'].count { |e| e['status'] == 'planned' }
    assert_equal 1, data['adjusted_year_dates']
    assert_equal 1, data['inferred_dates']
    assert_equal '2027-01-07', data['entries'].first['date']
    assert_equal '2027-01-15', data['entries'].last['date']
    assert data['warnings'].any? { |w| w.include?('W132') }
    assert data['warnings'].any? { |w| w.include?('somente dinheiro') }
    assert_not data['warnings'].any? { |w| w.include?('linha 211') }
    annual = data['auxiliary'].find { |s| s['sheet'] == 'RESUMO ANUAL' }
    assert_equal [53], annual['financial_rows'].map { |r| r['row'] }
    assert data['warnings'].any? { |w| w.include?('lançamentos avulsos') }
    year = XlsxImporter.commit!(data)
    assert_equal 7, year.entries.count
    assert_equal BigDecimal('9'), BalanceReport.new(year).variation
    assert_equal BigDecimal('1'), BalanceReport.new(year, status: 'planned').variation
  end

  test 'ano das datas só é substituído com escolha explícita' do
    file = reference_workbook
    data = XlsxImporter.new(file.path, filename: 'referencia-2027.xlsx', fallback_year: 2027).preview
    assert_equal 2026, data['year']
    assert_equal 0, data['adjusted_year_dates']
  end
end
