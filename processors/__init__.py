#!/usr/bin/env python3
"""
EasyMultiProfiler Processors - 完整整合版
包含：原R包功能 + 新增功能
"""

# 从各模块导入
from .chipseeq import ChipSeqProcessor
from .singlecell import SingleCellProcessor
from .multiomics import MultiOmicsProcessor
from .microbiome import MicrobiomeProcessor
from .visualization import VisualizationProcessor

__all__ = [
    'ChipSeqProcessor',
    'SingleCellProcessor', 
    'MultiOmicsProcessor',
    'MicrobiomeProcessor',
    'VisualizationProcessor'
]
