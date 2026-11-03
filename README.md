# Logistics & Fleet Operations Data Warehouse

Đồ án Data Warehouse xây dựng trên kiến trúc **Galaxy Schema** theo phương pháp luận Ralph Kimball. Hệ thống quản lý và phân tích toàn diện dữ liệu chuỗi cung ứng, bao gồm: mảng thương mại đơn hàng, vận hành chuyến xe, chu trình giao nhận và bảo trì đội xe.

## Thành viên thực hiện
- **Nguyễn Thanh Bình Minh** (Nhóm trưởng) - *Phụ trách mảng Thương mại & Đơn hàng*
- **Nguyễn Phúc An** - *Phụ trách mảng Kỹ thuật Bảo trì & Tài nguyên Đội xe*
- **Trần Quang Duy** - *Phụ trách mảng Vận hành Chuyến xe & Chu trình Giao nhận*

## 🛠 Kiến trúc công nghệ (Tech Stack)
- **Data Sources:** SQL Server OLTP (kích hoạt CDC), Flat files (CSV), External API (REST/JSON).
- **Data Integration & Crawler:** Python (Mock API Crawler).
- **Staging & Core DWH:** SQL Server 2022.
- **ETL Pipeline:** SQL Server Integration Services (SSIS).
- **Orchestration & Automation:** SQL Server Agent (Multi-step Job & Error Handling).
- **Semantic Layer (OLAP):** SQL Server Analysis Services (SSAS Multidimensional) - *Triển khai 4 Modular Cubes*.
- **Visualization:** Power BI / Excel.

## Cấu trúc dự án (Project Structure)

Dưới đây là cấu trúc mã nguồn toàn bộ hệ thống lưu trữ trên Repository:

```text
logistics-dw-bi-project/
│
├── config.example.json                 # File cấu hình mẫu cho các biến môi trường
├── README.md                           # Giới thiệu tổng quan dự án (File này)
│
├── data/                               # KHU VỰC LƯU TRỮ DỮ LIỆU NGUỒN & EXTERNAL DATA
│   ├── fuel/                           # Dữ liệu giá nhiên liệu thị trường thu thập từ API
│   │   ├── fuel_market_rates_2022_2024.csv
│   │   └── fuel_market_rates_2022_2024.json
│   ├── raw/                            # Dữ liệu thô (CSV) trích xuất từ hệ thống tác nghiệp cũ
│   │   ├── customers.csv, drivers.csv, facilities.csv, routes.csv, trucks.csv...
│   │   ├── delivery_events.csv         # Dữ liệu sự kiện giao nhận (chứa miligiây)
│   │   └── DATABASE_SCHEMA.txt         # Lược đồ cơ sở dữ liệu nguồn gốc
│   └── seed/                           # Dữ liệu hạt giống tĩnh
│
├── docs/                               # TÀI LIỆU QUY CHUẨN & BÀN GIAO KỸ THUẬT
│   ├── handover_dimension_dq_audit_guidelines.md
│   ├── handover_ssas_guidelines_to_team.md    # Cẩm nang cấu hình SSAS, MDX & Modular Cubes
│   ├── handover_ssis_guidelines_to_team.md    # Cẩm nang phát triển luồng SSIS & ETL
│   ├── phancong.md                            # Ma trận phân công công việc chi tiết
│   ├── thietke_dimfact.md                     # Thiết kế logic các bảng Fact, Dimension
│   └── thietke_luong_dam_bao_chat_luong.md    # Tài liệu đối soát chất lượng dữ liệu
│
├── mock_api/                           # EXTERNAL CRAWLER TÍCH HỢP DỮ LIỆU BÊN NGOÀI
│   ├── fuel_crawler.py                 # Script Python cào dữ liệu giá nhiên liệu tự động
│   ├── README_fuel_crawler.md          # Hướng dẫn chạy crawler
│   └── requirements.txt                # Các thư viện Python cần thiết (requests, pandas...)
│
├── sql/                                # TẬP HỢP SCRIPT SQL (Chạy tuần tự theo số thứ tự 01->16)
│   ├── 01_restore_oltp.sql             # Khởi tạo DB nguồn tác nghiệp
│   ├── 02_enable_cdc.sql               # Kích hoạt Change Data Capture trên DB nguồn
│   ├── 03_create_staging.sql           # DDL tạo cấu trúc vùng đệm Staging
│   ├── 04_create_dwh.sql               # DDL tạo Data Warehouse (Galaxy Schema: 4 Facts, 9 Dims)
│   ├── 05_populate_dim_date.sql        # Script tự động sinh dữ liệu thời gian cho Dim_Date
│   ├── 06_create_etl_metadata.sql      # Khởi tạo bảng lưu watermark phục vụ Incremental Load
│   ├── 07_create_delivery_events_mapping.sql # Stored Procedure chuẩn hóa mapping bến bãi
│   ├── 08_ssis_prerequisites_and_patches.sql
│   ├── 09_11_enable_cdc_*.sql          # Kích hoạt CDC cho từng bảng cụ thể
│   ├── 11_mapping_data_type.sql        # Xử lý ép kiểu dữ liệu đặc thù
│   ├── 12_13_15_query_*_tsql.sql       # Các kịch bản truy vấn phân tích bằng T-SQL
│   ├── 14_init_audit_schema.sql        # Cấu hình bảng Batch_Log giám sát luồng ETL
│   └── 16_create_sql_agent_job.sql     # Script tạo tự động SQL Server Agent Job 7 bước
│
├── SSAS_Logistics/                     # DỰ ÁN SEMANTIC LAYER (SSAS MULTIDIMENSIONAL)
│   ├── Scripts/                        # Lưu trữ truy vấn MDX phân tích nghiệp vụ
│   │   ├── 01_query_commercial_mdx.mdx
│   │   ├── 02_03_query_operates_fulfillment_mdx.mdx
│   │   └── 04_query_maintenance_mdx.mdx
│   ├── DSV_Logistics_DW.dsv            # Data Source View phân rã thành 4 Diagram Organizer
│   ├── Dim_*.dim                       # 9 Bảng chiều (Tích hợp Role-Playing, Multiple Hierarchies)
│   ├── Cube_Commercial.cube            # Khối lập phương mảng Thương mại
│   ├── Cube_Fleet_Operations.cube      # Khối lập phương mảng Vận hành
│   ├── Cube_Fulfillment.cube           # Khối lập phương mảng Giao nhận (Accumulating Snapshot)
│   └── Cube_Maintenance.cube           # Khối lập phương mảng Bảo trì
│
└── SSIS_Logistics/                     # DỰ ÁN ETL TÍCH HỢP DỮ LIỆU (SSIS)
    ├── Conn_*.conmgr                   # Connection Managers (OLTP, Staging, DWH)
    ├── Project.params                  # Cấu hình tham số môi trường
    ├── Stg_*.dtsx                      # Nhóm Package trích xuất dữ liệu vào Staging
    ├── Dim_*.dtsx                      # Nhóm Package biến đổi & nạp dữ liệu Dimension (SCD)
    ├── Fact_*.dtsx                     # Nhóm Package nạp dữ liệu Fact (Gia tăng / Chèn)
    ├── ETL_Data_Reconciliation.dtsx    # Package đối soát chất lượng dữ liệu cuối luồng
    └── Master_Orchestrator.dtsx        # Package tổng điều phối chạy song song các tiến trình
```

## Hướng dẫn Triển khai (Deployment Guide)

1. **Khởi tạo Database & Cấu trúc:**
   - Chạy các script SQL trong thư mục `sql/` theo thứ tự từ `01` đến `07` để thiết lập OLTP, Staging, DWH và chèn dữ liệu mốc thời gian.
   - Chạy script `14_init_audit_schema.sql` để tạo cấu trúc Log.
2. **Cấu hình Python Crawler:**
   - Cài đặt thư viện: `pip install -r mock_api/requirements.txt`
3. **Triển khai Luồng ETL (SSIS):**
   - Mở Solution `SSIS_Logistics.sln` bằng Visual Studio.
   - Build và Deploy project lên **SSIS Catalog (SSISDB)**.
4. **Triển khai Khối lập phương (SSAS):**
   - Mở Solution `SSAS_Logistics.slnx`.
   - Tiến hành Deploy lên SSAS Server cục bộ (`localhost`) và thực thi **Process Full** 4 Cubes.
5. **Cấu hình Lịch trình Tự động (Orchestration):**
   - Chạy script `sql/16_create_sql_agent_job.sql` trên SSMS để tự động tạo luồng `Logistics_Daily_ETL_Orchestration` với 7 bước phối hợp hoàn chỉnh (Python $\rightarrow$ SSIS $\rightarrow$ SSAS).