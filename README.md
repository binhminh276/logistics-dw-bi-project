# Logistics & Fleet Operations Data Warehouse

Do an Data Warehouse & BI xay dung tren mo hinh Galaxy Schema theo phuong phap Kimball.

## Thanh vien thuc hien
- Binh Minh (Nhom truong)
- Phuc An
- Quang Duy

## Kien truc he thong
- Source: SQL Server OLTP (CDC), CSV Flat files, Mock REST API (FastAPI)
- Staging & DW: SQL Server
- ETL: SSIS
- Orchestration: Apache Airflow (Docker)
- Semantic Layer: SSAS Multidimensional Cube
- Visualization: Power BI

```text
logistics-data-warehouse/
│
├── .gitignore                          # File bỏ qua rác build, cache VS và file nặng
├── README.md                           # Giới thiệu tổng quan dự án, kiến trúc và cách chạy
├── requirements.txt                    # Thư viện Python phục vụ sinh dữ liệu/kiểm thử (pandas, faker...)
│
├── data/                               # DỮ LIỆU MẪU & SEED DATA
│   ├── raw_sample/                     # Dữ liệu nguồn mẫu dạng CSV nhỏ (< 5-10MB để demo/test)
│   │   ├── sample_trips.csv
│   │   ├── sample_loads.csv
│   │   ├── sample_deliveries.csv
│   │   ├── sample_fuel_purchases.csv
│   │   ├── sample_maintenance.csv
│   │   └── sample_safety_incidents.csv
│   └── seed_lookup/                    # Dữ liệu tĩnh dùng để nạp danh mục tra cứu
│       ├── dim_date_seed.csv           # Dữ liệu lịch tạo sẵn từ 2020 đến 2030
│       └── incident_reasons_seed.csv   # Bảng mã chuẩn hóa nguyên nhân sự cố
│
├── sql/                                # TẬP HỢP TẤT CẢ SQL SCRIPTS (CHẠY THEO THỨ TỰ SỐ)
│   ├── 01_staging/                     # Tầng lưu trữ dữ liệu thô tạm thời (Staging Area)
│   │   ├── 01_create_staging_db.sql    # Script tạo Database Staging (Logistics_Staging)
│   │   └── 02_create_stg_tables.sql    # DDL các bảng Staging (độ linh hoạt cao, ít ràng buộc)
│   │
│   ├── 02_data_warehouse/              # Tầng kho dữ liệu chuẩn hóa (Core Data Warehouse)
│   │   ├── 01_create_dw_db.sql         # Script tạo Database DW chính (Logistics_DW)
│   │   ├── 02_create_dim_tables.sql    # DDL 8 bảng Dimension (Surrogate Keys, SCD Type 1 & 2)
│   │   ├── 03_create_fact_tables.sql   # DDL 6 bảng Fact (Foreign Keys, Measures, Degenerate Dims)
│   │   ├── 04_create_indexes.sql       # Script đánh chỉ mục (Clustered/Non-Clustered Indexes) tối ưu hóa
│   │   └── 05_seed_static_data.sql     # Script chèn dòng 'Unknown' (-1) và nạp Dim_Date
│   │
│   ├── 03_stored_procedures/           # THỦ TỤC NẠP DỮ LIỆU & XỬ LÝ SCD
│   │   ├── sp_load_dim_driver.sql      # Thủ tục xử lý SCD Type 1 & Type 2 cho Dim_Driver
│   │   ├── sp_load_dim_customer.sql    # Thủ tục cập nhật thông tin khách hàng và lịch sử tín dụng
│   │   ├── sp_load_dim_truck.sql       # Thủ tục nạp phương tiện
│   │   ├── sp_load_fact_loads.sql      # Nạp bảng Fact đơn hàng
│   │   ├── sp_load_fact_trips.sql      # Nạp bảng Fact chuyến xe (Accumulating Snapshot)
│   │   └── sp_master_etl_runner.sql    # Thủ tục tổng điều phối chạy toàn bộ pipeline
│   │
│   └── 04_views_and_analytics/         # VIEW PHỤC VỤ TRUY VẤN BÁO CÁO NHANH
│       ├── vw_fleet_kpi_summary.sql    # View tính toán chỉ số tổng hợp đội xe (MPG, Chi phí/dặm)
│       ├── vw_delivery_on_time_rate.sql# View đo lường tỷ lệ giao hàng đúng hẹn theo cơ sở/tuyến
│       └── vw_driver_safety_scorecard.sql # View xếp hạng an toàn tài xế
│
├── etl_ssis/                           # DỰ ÁN TRÍCH XUẤT, BIẾN ĐỔI & NẠP DỮ LIỆU (SSIS)
│   ├── Logistics_ETL.sln               # Solution file Visual Studio / SSDT
│   ├── Logistics_ETL.dtproj            # SSIS Project file
│   ├── Project.params                  # Tham số kết nối toàn cục (Connection String parameters)
│   └── packages/                       # Các gói SSIS Packages (.dtsx)
│       ├── 00_Master_Orchestrator.dtsx # Package cha điều phối chạy toàn bộ quy trình
│       ├── 01_Staging_Extract.dtsx     # Trích xuất dữ liệu từ file thô vào Staging
│       ├── 02_Load_Conformed_Dims.dtsx # Biến đổi và nạp 8 Conformed Dimensions
│       └── 03_Load_Fact_Tables.dtsx    # Biến đổi và nạp 6 Fact Tables
│
├── ssas_cube/                          # DỰ ÁN MÔ HÌNH PHÂN TÍCH ĐA CHIỀU (SSAS OLAP / TABULAR)
│   ├── Logistics_SSAS.sln              # Visual Studio Solution cho Analysis Services
│   ├── Logistics_SSAS.dwproj           # Project file SSAS
│   ├── DataSources/                    # Cấu hình kết nối tới Logistics_DW
│   ├── DataSourceViews/                # DSV định nghĩa quan hệ giữa 6 Facts và 8 Dims
│   ├── Dimensions/                     # Định nghĩa thuộc tính & Hierarchy của từng Dimension
│   ├── Cubes/                          # Cấu hình Cube đa chiều (Measures, Measure Groups, KPIs)
│   └── Calculations/                   # Script MDX / DAX cho các độ đo tính toán phức tạp
│
├── bi_reports/                         # BÁO CÁO TRỰC QUAN HÓA & DASHBOARDS
│   ├── powerbi/                        # Tệp báo cáo Microsoft Power BI
│   │   ├── Logistics_Executive_Overview.pbix   # Báo cáo điều hành tổng thể
│   │   ├── Fleet_Operations_Efficiency.pbix    # Báo cáo chi phí nhiên liệu & bảo dưỡng
│   │   └── Safety_and_Incident_Report.pbix     # Báo cáo an toàn đường bộ
│   └── ssrs_paginated/                 # Báo cáo dàn trang SSRS (.rdl) nếu có
│       └── Delivery_Manifest_Detail.rdl
│
└── scripts/                            # CÔNG CỤ HỖ TRỢ PYTHON & KIỂM TRA CHẤT LƯỢNG
    ├── data_generator/                 # Kịch bản sinh 85.000 bản ghi dữ liệu mẫu
    │   ├── generate_synthetic_data.py  # Script chính sinh data logic nghiệp vụ nhất quán
    │   └── config.yaml                 # Cấu hình tỷ lệ lỗi, dải ngày, danh sách trạm/kho
    └── data_quality_checks/            # Script kiểm thử tính toàn vẹn (Data Quality Audit)
        ├── test_null_keys.py           # Kiểm tra khóa ngoại mồ côi (Orphan Foreign Keys)
        └── test_measure_balances.py    # Đối soát tổng doanh thu và chi phí trước/sau ETL
```
