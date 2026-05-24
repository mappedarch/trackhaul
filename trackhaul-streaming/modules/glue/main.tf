resource "aws_glue_catalog_database" "this" {
  name = var.database_name
}

resource "aws_glue_catalog_table" "telemetry" {
  name          = var.table_name
  database_name = aws_glue_catalog_database.this.name

  table_type = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${var.bucket_name}/telemetry/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    # Schema must match your Lambda telemetry payload exactly
    columns {
      name = "truck_id"
      type = "string"
    }
    columns {
      name = "event_type"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
    columns {
      name = "speed_kmh"
      type = "double"
    }
    columns {
      name = "fuel_level_pct"
      type = "double"
    }
    columns {
      name = "engine_temp_c"
      type = "double"
    }
    columns {
      name = "anomaly_score"
      type = "double"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}