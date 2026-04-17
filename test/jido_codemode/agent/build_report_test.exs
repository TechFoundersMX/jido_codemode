defmodule JidoCodemode.Agent.BuildReportTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Agent.Report
  alias JidoCodemode.Agent.Tools.BuildReport

  test "build_report can build a minimal report from queried data" do
    session_id = "build-report-minimal-report-test"

    {:ok, result} =
      BuildReport.run(
        %{
          code: ~S'''
            local result = db.query({
              sql = [[SELECT CategoryName FROM Category ORDER BY CategoryName LIMIT 2]],
              purpose = "analysis"
            })

            return {
              version = 1,
               title = "Categories",
              blocks = {
                {
                  type = "table",
                  id = "categories",
                  title = "Categories",
                  source = result,
                  columns = {"CategoryName"},
                  row_limit = 2
                }
              }
            }
          '''
        },
        %{session_id: session_id}
      )

    assert %{title: "Categories", block_count: 1} = result

    assert {:ok, %Report{title: "Categories", blocks: [%Report.TableBlock{} = block]}} =
             Report.latest_for_session(session_id)

    refute Map.has_key?(block, :source)
  end

  test "build_report can render a report through the lua api" do
    session_id = "build-report-test"

    {:ok, result} =
      BuildReport.run(
        %{
          code: ~S'''
            local categories = db.query({
              sql = [[
                SELECT CategoryName, COUNT(*) AS product_count
                FROM Product
                JOIN Category ON Category.Id = Product.CategoryId
                GROUP BY CategoryName
                ORDER BY product_count DESC
              ]],
              purpose = "analysis"
            })

            return {
              version = 1,
               title = "Products by category",
               summary = "A category-level comparison of product counts.",
              blocks = {
                {
                  type = "bar",
                  id = "products_by_category",
                  title = "Products by category",
                  source = categories,
                  x = { field = "CategoryName", type = "nominal", format = "string" },
                  y = { field = "product_count", type = "quantitative", format = "number" }
                }
              }
            }
          '''
        },
        %{session_id: session_id}
      )

    assert %{title: "Products by category", block_count: 1} = result

    assert {:ok, %Report{title: "Products by category"}} =
             Report.latest_for_session(session_id)
  end

  test "build_report helpers can build a donut chart" do
    session_id = "build-report-donut-helper-test"

    {:ok, result} =
      BuildReport.run(
        %{
          code: ~S'''
            local categories = db.query({
              sql = [[
                SELECT CategoryName AS category, COUNT(*) AS product_count
                FROM Product
                JOIN Category ON Category.Id = Product.CategoryId
                GROUP BY CategoryName
                ORDER BY product_count DESC
              ]],
              purpose = "chart"
            })

            return report.build({
              version = 1,
               title = "Product distribution by category",
               blocks = {
                 report.donut({
                  id = "products_by_category",
                  title = "Product distribution by category",
                  source = categories,
                  label_field = "category",
                  value_field = "product_count",
                  value_format = "number"
                })
              }
            })
          '''
        },
        %{session_id: session_id}
      )

    assert %{title: "Product distribution by category", block_count: 1} = result

    assert {:ok, %Report{blocks: [%Report.ChartBlock{kind: :donut, spec_json: spec_json}]}} =
             Report.latest_for_session(session_id)

    assert spec_json =~ "arc"
  end

  test "build_report accepts pie aliases in raw report payloads" do
    session_id = "build-report-pie-alias-test"

    {:ok, result} =
      BuildReport.run(
        %{
          code: ~S'''
            local categories = db.query({
              sql = [[
                SELECT CategoryName AS category, COUNT(*) AS product_count
                FROM Product
                JOIN Category ON Category.Id = Product.CategoryId
                GROUP BY CategoryName
                ORDER BY product_count DESC
              ]],
              purpose = "chart"
            })

            return {
              version = 1,
               title = "Product distribution by category",
               blocks = {
                 {
                   type = "pie",
                  id = "products_by_category",
                  title = "Product distribution by category",
                  source = categories,
                  x = { field = "category", type = "nominal", format = "string" },
                  y = { field = "product_count", type = "quantitative", format = "number" }
                }
              }
            }
          '''
        },
        %{session_id: session_id}
      )

    assert %{title: "Product distribution by category", block_count: 1} = result

    assert {:ok, %Report{blocks: [%Report.ChartBlock{kind: :donut}]}} =
             Report.latest_for_session(session_id)
  end

  test "build_report rejects wrapped report payloads" do
    assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
             BuildReport.run(
               %{
                 code: ~S'''
                   return {
                     report = {
                       version = 1,
                        title = "Categories",
                       blocks = {
                         report.text({ id = "summary", body = "Legacy wrapper" })
                       }
                     }
                   }
                 '''
               },
               %{session_id: "build-report-wrapped-payload-test"}
             )

    assert error.message =~ "BuildReport must return a valid report payload"
    assert error.details.reason =~ "version"
  end
end
