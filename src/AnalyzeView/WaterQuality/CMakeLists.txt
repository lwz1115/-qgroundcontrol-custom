# ============================================================================
# 水质监测模块：导入 Excel/CSV 表格，用折线图 / 热力图显示
# ============================================================================

target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        WaterQualityLog.cc
        WaterQualityLog.h
)

target_include_directories(${CMAKE_PROJECT_NAME}
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
)
