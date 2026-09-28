import os
from pathlib import Path

# Khoi tao toan bo cay thu muc va file mau cho du an DWH Logistics
def setup_project_structure():
    folders = [
        "docs",
        "data/raw",
        "data/seed",
        "sql/01_staging",
        "sql/02_dw",
        "sql/03_stored_procedures",
        "sql/04_analysis",
        "etl_ssis",
        "airflow/dags",
        "mock_api",
        "ssas_cube",
        "bi_reports",
    ]

    for folder in folders:
        os.makedirs(folder, exist_ok=True)

    files_content = {
        ".gitignore": """# OS & IDE
.DS_Store
Thumbs.db
.vscode/
*.swp
*.bak

# Visual Studio / SSIS / SSAS
.vs/
bin/
obj/
*.user
*.suo
*.userosscache
*.sln.docstates
*.asdatabase
*.dbmdl

# Python
__pycache__/
*.py[cod]
.ipynb_checkpoints/
venv/
.venv/
env/

# Data & Logs
*.log
*.tmp
data/raw/*
!data/raw/.gitkeep

# Secrets
*.env
config.local.json
secrets.json
""",
        "README.md": """# Logistics & Fleet Operations Data Warehouse

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
""",
        "requirements.txt": """fastapi>=0.100.0
uvicorn>=0.23.0
requests>=2.31.0
pandas>=2.0.0
python-dotenv>=1.0.0
""",
        "docker-compose.yml": """version: '3.8'
services:
  airflow-webserver:
    image: apache/airflow:2.8.1
    container_name: airflow_webserver
    restart: always
    environment:
      - AIRFLOW__CORE__LOAD_EXAMPLES=False
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./airflow/logs:/opt/airflow/logs
      - ./airflow/plugins:/opt/airflow/plugins
    ports:
      - "8080:8080"
    command: webserver
""",
        "config.example.json": """{
  "oltp_connection": "Server=localhost;Database=Logistics_OLTP;Trusted_Connection=True;",
  "staging_connection": "Server=localhost;Database=Logistics_Staging;Trusted_Connection=True;",
  "dw_connection": "Server=localhost;Database=Logistics_DW;Trusted_Connection=True;",
  "fuel_api_url": "http://localhost:8000/api/fuel-prices"
}
""",
        "mock_api/main.py": """from fastapi import FastAPI
from datetime import date

app = FastAPI(title="Fuel Price Mock API")

@app.get("/api/fuel-prices")
def get_fuel_price(query_date: str = str(date.today())):
    return {
        "price_date": query_date,
        "fuel_type": "Diesel",
        "price_per_gallon": 3.85,
        "region": "US-National"
    }
""",
        "airflow/dags/logistics_pipeline.py": """from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "start_date": datetime(2026, 1, 1),
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    "logistics_dwh_orchestrator",
    default_args=default_args,
    schedule_interval=None,
    catchup=False,
) as dag:
    
    check_sources = BashOperator(
        task_id="check_sources",
        bash_command="echo 'Checking database and API connections...'"
    )
""",
        "sql/01_staging/01_create_staging_tables.sql": "-- Script tao cac bang Staging va ETL_Metadata\n",
        "sql/02_dw/01_create_dimensions.sql": "-- Script tao 8 bang Conformed Dimensions (Galaxy Schema)\n",
        "sql/02_dw/02_create_facts.sql": "-- Script tao 6 bang Fact Tables\n",
        "sql/03_stored_procedures/01_load_staging.sql": "-- Stored Procedures ho tro ETL\n",
        "sql/04_analysis/01_business_queries.sql": "-- Cac cau truy van T-SQL phan tich nghiep vu\n",
        "data/raw/.gitkeep": "",
        "data/seed/.gitkeep": "",
        "etl_ssis/.gitkeep": "",
        "ssas_cube/.gitkeep": "",
        "bi_reports/.gitkeep": "",
    }

    for file_path, content in files_content.items():
        path = Path(file_path)
        if not path.exists():
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)

    print("Project structure and template files have been created successfully.")

if __name__ == "__main__":
    setup_project_structure()