# HƯỚNG DẪN THIẾT LẬP VÀ VẬN HÀNH PIPELINE ETL TỰ ĐỘNG BẰNG SQL SERVER AGENT

Tài liệu này hướng dẫn chi tiết từng bước thiết lập, deploy mã nguồn, phân quyền và lập lịch chạy tự động hàng ngày vào **07:00 AM** cho Pipeline ETL Logistics (Python Crawler -> SSIS DWH -> SSAS Cube).

## THÔNG TIN CHUNG

* **Tên Job:** `Logistics_Daily_ETL_Orchestration`

* **Tài khoản chạy Job (Service Account):** `NT SERVICE\SQLSERVERAGENT`

* **Lịch tự động:** 07:00:00 AM hàng ngày (Daily)

* **Cấu trúc Pipeline:** Gồm 7 bước điều phối độc lập kèm cơ chế ghi Log Audit & Xử lý lỗi (Failure Catching).

## PHẦN 1: TIỀN ĐIỀU KIỆN, DEPLOY DỰ ÁN & PHÂN QUYỀN

Trước khi khởi tạo SQL Agent Job, tất cả các thành viên phải thực hiện deploy đầy đủ mã nguồn SSIS, SSAS và cấp quyền hệ thống.

### 1. Deploy toàn bộ dự án SSIS lên SSISDB

> ⚠️ **LƯU Ý QUAN TRỌNG:** Phải Deploy cả **Project SSIS** chứ không deploy lẻ từng file `.dtsx` để đảm bảo `Master_Orchestrator.dtsx` có đủ các package con.

1. Mở Solution SSIS bằng Visual Studio.

2. Trong cửa sổ **Solution Explorer**, nhấp chuột phải vào tên **Project** (ví dụ: `SSIS_Logistics`) -> Chọn **Deploy**.

3. Tại trình hướng dẫn **Integration Services Deployment Wizard**:

   * **Select Source:** Giữ nguyên mặc định -> Nhấn **Next**.

   * **Select Destination:**

     * Server name: `localhost` .

     * Path: Nhấn **Browse...** -> Chọn thư mục **SSISDB** -> Chọn thư mục dự án (ví dụ: `SSIS_Logistics`).

     * Path: `\SSISDB\SSIS_Logistics\SSIS_Logistics`

   * Nhấn **Deploy** cho đến khi tất cả chuyển thành xanh (*Passed*).

### 2. Deploy dự án SSAS (Lưu ý về đặt tên Database)

> ⚠️ **LƯU Ý CỰC KỲ QUAN TRỌNG VỀ TÊN CSDL SSAS:**
> Thư mục mã nguồn của bạn có thể tên là `SSAS_Logistics`, nhưng **Target Database Name trên SSAS bắt buộc phải đổi thành `Logistics_SSAS`** để khớp với lệnh XMLA mà SQL Agent Job thực thi (Step 5).

1. Mở dự án SSAS bằng Visual Studio.

2. Trong **Solution Explorer**, nhấp chuột phải vào tên Project SSAS -> Chọn **Properties**.

3. Chọn mục **Deployment** ở danh mục bên trái:

   * **Target / Server:** Điền `localhost`

   * **Target / Database:** Điền chính xác là **`Logistics_SSAS`** *(Không để mặc định là SSAS_Logistics)*.

4. Nhấn **OK** để lưu lại cấu hình.

5. Nhấp chuột phải vào Project SSAS -> Chọn **Deploy**.

6. Kiểm tra lại trên SSMS: Kết nối vào **Analysis Services** -> Mở mục **Databases** -> Phải thấy Database tên **`Logistics_SSAS`** hiển thị ở đây.

### 3. Phân quyền Thư mục cho Service Account (Cho Step 2 - Python)

Tài khoản chạy SQL Agent mặc định là `NT SERVICE\SQLSERVERAGENT`, tài khoản này cần quyền truy cập vào thư mục mã nguồn và môi trường Python.

1. Mở Windows Explorer, tìm đến thư mục dự án: `D:\Kho\logistics-dw-bi-project`.

2. Nhấp chuột phải vào thư mục -> Chọn **Properties** -> Chọn tab **Security**.

3. Nhấn **Edit...** -> Nhấn **Add...**.

4. Ở ô nhập tên, gõ: `NT SERVICE\SQLSERVERAGENT` rồi nhấn **Check Names** -> Nhấn **OK**.

5. Tích chọn quyền **Full Control** (hoặc *Read, Write, Modify, Execute*).

6. Nhấn **Apply** -> **OK**.

7. *Làm tương tự với thư mục chứa `python.exe`* (Ví dụ: `C:\Users\tranq\AppData\Local\Programs\Python\Python313`).

### 4. Phân quyền Admin trên Analysis Services (Cho Step 5 - SSAS)

SQL Agent cần quyền Administrator trên SSAS để thực thi lệnh XMLA Process Cube.

1. Mở **SSMS**, kết nối tới **Analysis Services** (Server Name: `localhost`).

2. Nhấp chuột phải vào tên Server ở trên cùng -> Chọn **Properties**.

3. Chọn trang **Security** từ danh mục bên trái.

4. Nhấn **Add...**, nhập `NT SERVICE\SQLSERVERAGENT` -> Nhấn **OK**.

5. Nhấn **OK** để lưu lại.

## PHẦN 2: THIẾT LẬP JOB BẰNG T-SQL SCRIPT

Để đảm bảo chính xác 100% cấu hình, nhóm nên khởi tạo Job bằng script T-SQL đã được tối ưu hóa.

1. Mở **SQL Server Management Studio (SSMS)** và kết nối tới Database Engine (`localhost`).

2. Mở file script `16_create_sql_agent_job.sql`.

3. Nhấn **F5** (hoặc nút **Execute**) để thực thi script.

## PHẦN 3: CHI TIẾT CẤU HÌNH 7 BƯỚC TRONG JOB (JOB STEPS BREAKDOWN)

Sau khi chạy script, Job sẽ tạo ra 7 bước điều phối theo sơ đồ logic sau:

```
[Step 1: Init_Batch_Log]
       │
       ▼
[Step 2: Run_Fuel_Crawler (Python)]
       │
       ▼
[Step 3: SSIS_Load_DWH (Master_Orchestrator)]
       │
       ▼
[Step 4: SSIS_Reconciliation (ETL_Data_Reconciliation)]
       │
       ▼
[Step 5: Process_SSAS_Cube (XMLA)]
       │ 
       ├── (Nếu Thành công) ──> [Step 7: Finalize_Batch_Success] ──> [END: SUCCESS]
       └── (Nếu Lỗi bất kỳ step nào) ──> [Step 6: Alert_Failure] ──> [END: FAILED]

```

### Chi tiết cấu hình từng Step:

Trong SSMS -> Mở rộng **SQL Server Agent** -> **Jobs** -> Chuột phải vào `Logistics_Daily_ETL_Orchestration` -> **Properties** -> **Steps**.

#### Step 1: `1. Init_Batch_Log`

* **Type:** Transact-SQL script (T-SQL)

* **Database:** `Logistics_Staging`

* **Command:**

  ```
  INSERT INTO Logistics_Staging.audit.Batch_Log (batch_name, status) 
  VALUES ('Daily_ETL', 'RUNNING');
  
  ```

#### Step 2: `2. Run_Fuel_Crawler`

* **Type:** Operating system (CmdExec)

* **Run as:** SQL Server Agent Service Account

* **Command (Bắt buộc dùng đường dẫn tuyệt đối):**

  ```
  "C:\Users\tranq\AppData\Local\Programs\Python\Python313\python.exe" "D:\Kho\logistics-dw-bi-project\mock_api\fuel_crawler.py"
  
  ```

  *(Lưu ý: Thay đổi đường dẫn Python phù hợp với máy cá nhân nếu khác)*.

#### Step 3: `3. SSIS_Load_DWH`

* **Type:** SQL Server Integration Services Package (SSIS)

* **Run as:** SQL Server Agent Service Account

* **Package Path:** `\SSISDB\SSIS_Logistics\SSIS_Logistics\Master_Orchestrator.dtsx`

#### Step 4: `4. SSIS_Reconciliation`

* **Type:** SQL Server Integration Services Package (SSIS)

* **Run as:** SQL Server Agent Service Account

* **Package Path:** `\SSISDB\SSIS_Logistics\SSIS_Logistics\ETL_Data_Reconciliation.dtsx`

#### Step 5: `5. Process_SSAS_Cube`

* **Type:** SQL Server Analysis Services Command

* **Run as:** SQL Server Agent Service Account

* **Server:** `localhost`

* **Command (XMLA):**

  ```
  <Process xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">
    <Object>
      <DatabaseID>Logistics_SSAS</DatabaseID>
    </Object>
    <Type>ProcessFull</Type>
  </Process>
  
  ```

#### Step 6: `6. Alert_Failure` (Nhánh xử lý lỗi)

* **Type:** Transact-SQL script (T-SQL) | **Database:** `Logistics_Staging`

* **Command:**

  ```
  UPDATE Logistics_Staging.audit.Batch_Log 
  SET end_time = SYSDATETIME(), status = 'FAILED' 
  WHERE batch_id = (SELECT MAX(batch_id) FROM Logistics_Staging.audit.Batch_Log);
  
  ```

#### Step 7: `7. Finalize_Batch_Success` (Nhánh hoàn thành)

* **Type:** Transact-SQL script (T-SQL) | **Database:** `Logistics_Staging`

* **Command:**

  ```
  UPDATE Logistics_Staging.audit.Batch_Log 
  SET end_time = SYSDATETIME(), status = 'SUCCESS' 
  WHERE batch_id = (SELECT MAX(batch_id) FROM Logistics_Staging.audit.Batch_Log);
  ```
#### Chạy thử 
* Trong SSMS -> Mở rộng SQL Server Agent -> Mở thư mục Jobs.

* Chuột phải vào `Logistics_Daily_ETL_Orchestration`  -> Chọn Start Job at Steps...

## PHẦN 4: THIẾT LẬP LẬP LỊCH TỰ ĐỘNG (SCHEDULE 7:00 AM)

Để Job tự động kích hoạt đúng 7 giờ sáng hàng ngày:

1. Trong SSMS -> Nhấp chuột phải vào Job `Logistics_Daily_ETL_Orchestration` -> Chọn **Properties**.

2. Chọn danh mục **Schedules** ở menu bên trái -> Nhấn **New...**.

3. Điền các thông số lập lịch:

   * **Name:** `Daily_7AM_Schedule`

   * **Schedule type:** `Recurring` (Định kỳ)

   * **Frequency (Occurs):** `Daily` (Hàng ngày) | **Recurs every:** `1` day(s)

   * **Daily frequency:** Chọn **Occurs once at:** `07:00:00`

   * **Duration:** Start date chọn ngày hiện tại, End date chọn `No end date`.

4. Nhấn **OK** -> Nhấn **OK** để hoàn tất lưu cấu hình.

## PHẦN 5: CÁC LỖI THƯỜNG GẶP & CÁCH XỬ LÝ (TROUBLESHOOTING)

### 1. Lỗi: `Environment reference '1' is not associated with the project` (Step 3 / Step 4)

* **Nguyên nhân:** GUI SQL Agent Job bị lưu kẹt ID Environment cũ. Nút check trong GUI bị mờ không tháo ra được.

* **Cách khắc phục:** Dùng tùy chọn **Script Job as -> DROP And CREATE To** ra Query Editor, bấm `Ctrl + F` tìm `/ENVREFERENCE 1` và xóa chữ đó đi, sau đó nhấn **F5 (Execute)** để tạo lại Job sạch.

### 2. Lỗi: `Connection is busy with results for another command` (Step 3 / Master Package)

* **Nguyên nhân:** Các Package/Task nạp Dimension chạy song song tranh chấp connection manager.

* **Cách khắc phục:**

  1. Trong Visual Studio SSIS Project, chỉnh thuộc tính **DelayValidation = True** cho các Data Flow Task/Package.

  2. Với OLE DB Connection Manager, đặt **RetainSameConnection = False**.

  3. Trong `Master_Orchestrator.dtsx`, đấu nối các task Dimension chạy **tuần tự (Sequential)** bằng mũi tên xanh thay vì cho chạy song song.

### 3. Lỗi: `Either the database with the ID of 'Logistics_SSAS' does not exist...` (Step 5)

* **Nguyên nhân:** SSAS Project chưa được deploy hoặc cấu hình Target Database Name bị sai tên.

* **Cách khắc phục:** Mở Visual Studio SSAS Project -> Properties -> Deployment -> Đảm bảo **Target Database Name** điền đúng là **`Logistics_SSAS`** rồi thực hiện Deploy lại.

## PHẦN 6: KIỂM TRA & VẬN HÀNH THỦ CÔNG

* Chạy kiểm tra thủ công bất kỳ lúc nào: Nhấp chuột phải vào Job `Logistics_Daily_ETL_Orchestration` -> Chọn **Start Job at Step...** -> Chọn **Step 1**.

* Chạy thủ công **không ảnh hưởng hay làm hủy lịch tự động 7:00 AM**.

* Theo dõi nhật ký chạy chi tiết: Nhấp chuột phải vào Job -> Chọn **View History**.