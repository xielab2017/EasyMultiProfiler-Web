#!/usr/bin/env python3
"""
EasyMultiProfiler Web Application - 完整整合版
包含：原R包功能 + 新增功能
"""

from flask import Flask, render_template, request, jsonify
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from processors import (
    ChipSeqProcessor, 
    SingleCellProcessor, 
    MultiOmicsProcessor,
    MicrobiomeProcessor,
    VisualizationProcessor
)

app = Flask(__name__)

# 双语文本
TEXT = {
    "zh": {
        "title": "🧬 EasyMultiProfiler",
        "subtitle": "完整版多组学分析平台",
        "intro": "整合原R包全部功能 + 新增ChIP-seq/单细胞/多组学",
        "features": {
            "microbiome": {"title": "🦠 微生物组", "desc": "α/β多样性, 差异, 网络, WGCNA"},
            "chipseq": {"title": "🧬 ChIP-seq", "desc": "MACS2, 注释, GO/KEGG, Motif"},
            "singlecell": {"title": "🦠 单细胞", "desc": "降维, 聚类, 标记基因"},
            "multiomics": {"title": "🧪 多组学", "desc": "整合分析, 相关性"},
            "visualization": {"title": "📊 可视化", "desc": "热图, 火山图, 网络图"}
        },
        "tabs": {
            "microbiome": "🦠 微生物组",
            "chipseq": "🧬 ChIP-seq",
            "singlecell": "🦠 单细胞",
            "multiomics": "🧪 多组学",
            "visualization": "📊 可视化"
        },
        "labels": {
            "analysis": "分析类型",
            "input": "输入文件",
            "run": "🚀 开始分析",
            "download": "📥 下载结果",
            "select": "请选择..."
        },
        "options": {
            "microbiome": {
                "alpha": "Alpha多样性",
                "beta": "Beta多样性",
                "diff": "差异分析",
                "network": "网络分析",
                "cluster": "聚类分析",
                "wgcna": "WGCNA分析",
                "marker": "标记物分析",
                "enrich": "富集分析",
                "complete": "完整流程"
            },
            "chipseq": {
                "macs2": "MACS2 Peak Calling",
                "annotation": "Peak注释",
                "go": "GO富集",
                "kegg": "KEGG通路",
                "motif": "Motif分析",
                "diff": "差异分析",
                "viz": "可视化"
            },
            "singlecell": {
                "dimred": "降维(UMAP/tSNE)",
                "cluster": "聚类",
                "markers": "标记基因",
                "trajectory": "轨迹分析"
            },
            "multiomics": {
                "correlation": "相关性分析",
                "network": "网络整合",
                "joint": "联合分析"
            },
            "visualization": {
                "heatmap": "热图",
                "volcano": "火山图",
                "pca": "PCA图",
                "network": "网络图",
                "barplot": "柱状图",
                "boxplot": "箱线图"
            }
        },
        "loading": "分析中，请稍候...",
        "success": "分析完成!",
        "version": "完整版 v2.0"
    },
    "en": {
        "title": "🧬 EasyMultiProfiler",
        "subtitle": "Full Multi-omics Analysis Platform",
        "intro": "Integrates all R package functions + ChIP-seq/Single-cell/Multi-omics",
        "features": {
            "microbiome": {"title": "🦠 Microbiome", "desc": "α/β Diversity, Diff, Network, WGCNA"},
            "chipseq": {"title": "🧬 ChIP-seq", "desc": "MACS2, Annotation, GO/KEGG, Motif"},
            "singlecell": {"title": "🦠 Single Cell", "desc": "DimRed, Clustering, Markers"},
            "multiomics": {"title": "🧪 Multi-omics", "desc": "Integration, Correlation"},
            "visualization": {"title": "📊 Visualization", "desc": "Heatmap, Volcano, Network"}
        },
        "tabs": {
            "microbiome": "🦠 Microbiome",
            "chipseq": "🧬 ChIP-seq",
            "singlecell": "🦠 Single Cell",
            "multiomics": "🧪 Multi-omics",
            "visualization": "📊 Visualization"
        },
        "labels": {
            "analysis": "Analysis Type",
            "input": "Input File",
            "run": "🚀 Run",
            "download": "📥 Download",
            "select": "Select..."
        },
        "options": {
            "microbiome": {
                "alpha": "Alpha Diversity",
                "beta": "Beta Diversity",
                "diff": "Differential Analysis",
                "network": "Network Analysis",
                "cluster": "Clustering",
                "wgcna": "WGCNA",
                "marker": "Marker Analysis",
                "enrich": "Enrichment",
                "complete": "Complete Pipeline"
            },
            "chipseq": {
                "macs2": "MACS2 Peak Calling",
                "annotation": "Peak Annotation",
                "go": "GO Enrichment",
                "kegg": "KEGG Pathway",
                "motif": "Motif Analysis",
                "diff": "Differential",
                "viz": "Visualization"
            },
            "singlecell": {
                "dimred": "DimRed (UMAP/tSNE)",
                "cluster": "Clustering",
                "markers": "Marker Genes",
                "trajectory": "Trajectory"
            },
            "multiomics": {
                "correlation": "Correlation",
                "network": "Network Integration",
                "joint": "Joint Analysis"
            },
            "visualization": {
                "heatmap": "Heatmap",
                "volcano": "Volcano Plot",
                "pca": "PCA Plot",
                "network": "Network",
                "barplot": "Bar Plot",
                "boxplot": "Box Plot"
            }
        },
        "loading": "Running analysis...",
        "success": "Analysis complete!",
        "version": "Full Version v2.0"
    }
}

@app.route('/')
def index():
    lang = request.args.get('lang', 'zh')
    if lang not in ['zh', 'en']:
        lang = 'zh'
    
    return render_template('index.html', lang=lang, **TEXT[lang])

# ==================== 微生物组 API ====================

@app.route('/api/microbiome/alpha', methods=['POST'])
def microbiome_alpha():
    proc = MicrobiomeProcessor()
    data = request.json or {}
    result = proc.alpha_diversity(data)
    return jsonify(result)

@app.route('/api/microbiome/beta', methods=['POST'])
def microbiome_beta():
    proc = MicrobiomeProcessor()
    data = request.json or {}
    result = proc.beta_diversity(data)
    return jsonify(result)

@app.route('/api/microbiome/diff', methods=['POST'])
def microbiome_diff():
    proc = MicrobiomeProcessor()
    data = request.json or {}
    result = proc.differential_analysis(data, data.get('group', []))
    return jsonify(result)

@app.route('/api/microbiome/network', methods=['POST'])
def microbiome_network():
    proc = MicrobiomeProcessor()
    data = request.json or {}
    result = proc.network_analysis(data)
    return jsonify(result)

@app.route('/api/microbiome/wgcna', methods=['POST'])
def microbiome_wgcna():
    proc = MicrobiomeProcessor()
    data = request.json or {}
    result = proc.wgcna(data)
    return jsonify(result)

# ==================== ChIP-seq API ====================

@app.route('/api/chipseq/macs2', methods=['POST'])
def chipseq_macs2():
    proc = ChipSeqProcessor()
    data = request.json or {}
    result = proc.macs2_call_bam(data.get('input', 'demo.bam'))
    return jsonify(result)

@app.route('/api/chipseq/annotation', methods=['POST'])
def chipseq_annotation():
    proc = ChipSeqProcessor()
    data = request.json or {}
    result = proc.annotate_peaks(data.get('input', 'demo.peaks'))
    return jsonify(result)

@app.route('/api/chipseq/go', methods=['POST'])
def chipseq_go():
    proc = ChipSeqProcessor()
    data = request.json or {}
    result = proc.go_enrichment(data.get('input', 'demo.peaks'))
    return jsonify(result)

@app.route('/api/chipseq/kegg', methods=['POST'])
def chipseq_kegg():
    proc = ChipSeqProcessor()
    data = request.json or {}
    result = proc.kegg_enrichment(data.get('input', 'demo.peaks'))
    return jsonify(result)

@app.route('/api/chipseq/motif', methods=['POST'])
def chipseq_motif():
    proc = ChipSeqProcessor()
    data = request.json or {}
    result = proc.motif_analysis(data.get('input', 'demo.peaks'))
    return jsonify(result)

# ==================== 单细胞 API ====================

@app.route('/api/singlecell/dimred', methods=['POST'])
def singlecell_dimred():
    proc = SingleCellProcessor()
    data = request.json or {}
    result = proc.dimensionality_reduction(data, 'UMAP')
    return jsonify(result)

@app.route('/api/singlecell/cluster', methods=['POST'])
def singlecell_cluster():
    proc = SingleCellProcessor()
    data = request.json or {}
    result = proc.clustering(data)
    return jsonify(result)

@app.route('/api/singlecell/markers', methods=['POST'])
def singlecell_markers():
    proc = SingleCellProcessor()
    data = request.json or {}
    result = proc.marker_detection(data, [0,1,2])
    return jsonify(result)

# ==================== 多组学 API ====================

@app.route('/api/multiomics/correlation', methods=['POST'])
def multiomics_correlation():
    proc = MultiOmicsProcessor()
    data = request.json or {}
    result = proc.correlation_analysis({}, {})
    return jsonify(result)

@app.route('/api/multiomics/joint', methods=['POST'])
def multiomics_joint():
    proc = MultiOmicsProcessor()
    result = proc.joint_analysis({}, {}, {})
    return jsonify(result)

# ==================== 可视化 API ====================

@app.route('/api/viz/heatmap', methods=['POST'])
def viz_heatmap():
    proc = VisualizationProcessor()
    data = request.json or {}
    result = proc.heatmap(data)
    return jsonify(result)

@app.route('/api/viz/volcano', methods=['POST'])
def viz_volcano():
    proc = VisualizationProcessor()
    data = request.json or {}
    result = proc.volcano(data)
    return jsonify(result)

@app.route('/api/viz/pca', methods=['POST'])
def viz_pca():
    proc = VisualizationProcessor()
    data = request.json or {}
    result = proc.pca_plot(data)
    return jsonify(result)

if __name__ == '__main__':
    print("""
🧬 EasyMultiProfiler Web - 完整版 v2.0
   
   中文: http://localhost:5000
   English: http://localhost:5000?lang=en
   
   功能模块:
   - 微生物组 (原R包功能)
   - ChIP-seq (新增)
   - 单细胞 (新增)
   - 多组学 (新增)
   - 可视化 (原R包功能)
   
   按 Ctrl+C 停止
    """)
    app.run(host='0.0.0.0', port=5000, debug=True)
