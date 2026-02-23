#!/usr/bin/env python3
"""
EasyMultiProfiler Web Application - 双语版
支持中英文切换
"""

from flask import Flask, render_template_string, request, jsonify
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from processors import ChipSeqProcessor, SingleCellProcessor, MultiOmicsProcessor

app = Flask(__name__)

# 双语文本
TEXT = {
    "zh": {
        "title": "🧬 EasyMultiProfiler 网页版",
        "subtitle": "零门槛多组学分析平台",
        "features": {
            "chipseq": {"title": "🧬 ChIP-seq", "desc": "Peak calling, Motif分析"},
            "singlecell": {"title": "🦠 单细胞", "desc": "降维, 聚类, 标记基因"},
            "multiomics": {"title": "🧪 多组学", "desc": "RNA-seq + 微生物组整合"}
        },
        "tabs": {
            "chipseq": "🧬 ChIP-seq",
            "singlecell": "🦠 单细胞", 
            "multiomics": "🧪 多组学"
        },
        "labels": {
            "analysis_type": "分析类型",
            "input_file": "输入文件",
            "run": "🚀 开始分析",
            "result": "结果"
        },
        "chipseq_options": {
            "macs2": "MACS2 Peak Calling",
            "annotation": "Peak注释",
            "go": "GO富集",
            "kegg": "KEGG通路",
            "motif": "Motif分析",
            "differential": "差异分析",
            "visualization": "可视化"
        },
        "sc_options": {
            "dimred": "降维 (UMAP/tSNE)",
            "cluster": "聚类分析",
            "markers": "标记基因",
            "trajectory": "轨迹分析"
        },
        "mo_options": {
            "correlation": "相关性分析",
            "network": "网络整合",
            "joint": "联合分析"
        },
        "loading": "分析中...",
        "download": "📥 下载结果"
    },
    "en": {
        "title": "🧬 EasyMultiProfiler Web",
        "subtitle": "Zero-threshold Multi-omics Analysis Platform",
        "features": {
            "chipseq": {"title": "🧬 ChIP-seq", "desc": "Peak calling, Motif analysis"},
            "singlecell": {"title": "🦠 Single Cell", "desc": "DimRed, Clustering, Markers"},
            "multiomics": {"title": "🧪 Multi-omics", "desc": "RNA-seq + Microbiome integration"}
        },
        "tabs": {
            "chipseq": "🧬 ChIP-seq",
            "singlecell": "🦠 Single Cell",
            "multiomics": "🧪 Multi-omics"
        },
        "labels": {
            "analysis_type": "Analysis Type",
            "input_file": "Input File",
            "run": "🚀 Run",
            "result": "Result"
        },
        "chipseq_options": {
            "macs2": "MACS2 Peak Calling",
            "annotation": "Peak Annotation",
            "go": "GO Enrichment",
            "kegg": "KEGG Pathway",
            "motif": "Motif Analysis",
            "differential": "Differential Analysis",
            "visualization": "Visualization"
        },
        "sc_options": {
            "dimred": "Dimensionality Reduction (UMAP/tSNE)",
            "cluster": "Clustering",
            "markers": "Marker Genes",
            "trajectory": "Trajectory Analysis"
        },
        "mo_options": {
            "correlation": "Correlation Analysis",
            "network": "Network Integration",
            "joint": "Joint Analysis"
        },
        "loading": "Running...",
        "download": "📥 Download Results"
    }
}

# HTML模板
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="{{lang}}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EasyMultiProfiler</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding:0; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 900px; margin: 0 auto; }
        .card {
            background: white;
            border-radius: 16px;
            padding: 30px;
            margin-bottom: 20px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 { color: #1a1a2e; text-align: center; margin-bottom: 10px; }
        .subtitle { text-align: center; color: #666; margin-bottom: 30px; }
        
        .lang-switch {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 100;
        }
        .lang-btn {
            padding: 8px 16px;
            background: white;
            border: 2px solid #667eea;
            border-radius: 20px;
            cursor: pointer;
            font-weight: bold;
            color: #667eea;
        }
        .lang-btn:hover { background: #667eea; color: white; }
        
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .feature-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            border-radius: 12px;
            text-align: center;
        }
        .feature-card h3 { margin-bottom: 10px; }
        
        .tab-nav { display: flex; gap: 10px; margin-bottom: 20px; }
        .tab-btn {
            flex: 1;
            padding: 12px;
            border: none;
            background: #f0f0f0;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
        }
        .tab-btn.active { background: #667eea; color: white; }
        
        .form-group { margin-bottom: 20px; }
        label { display: block; margin-bottom: 8px; color: #333; }
        input, select { width: 100%; padding: 12px; border: 2px solid #e0e0e0; border-radius: 8px; }
        
        .btn {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
        }
        
        .result { background: #f8f9fa; border-radius: 8px; padding: 20px; margin-top: 20px; display: none; }
        .result.show { display: block; }
        .loading { text-align: center; padding: 20px; color: #666; }
        pre { overflow-x: auto; }
    </style>
</head>
<body>
    <div class="lang-switch">
        <button class="lang-btn" onclick="switchLang()">{{lang == 'zh' ? 'EN' : '中文'}}</button>
    </div>
    
    <div class="container">
        <div class="card">
            <h1>{{title}}</h1>
            <p class="subtitle">{{subtitle}}</p>
            
            <div class="features">
                <div class="feature-card">
                    <h3>{{features.chipseq.title}}</h3>
                    <p>{{features.chipseq.desc}}</p>
                </div>
                <div class="feature-card">
                    <h3>{{features.singlecell.title}}</h3>
                    <p>{{features.singlecell.desc}}</p>
                </div>
                <div class="feature-card">
                    <h3>{{features.multiomics.title}}</h3>
                    <p>{{features.multiomics.desc}}</p>
                </div>
            </div>
            
            <div class="tab-nav">
                <button class="tab-btn active" onclick="switchTab('chipseq')">{{tabs.chipseq}}</button>
                <button class="tab-btn" onclick="switchTab('singlecell')">{{tabs.singlecell}}</button>
                <button class="tab-btn" onclick="switchTab('multiomics')">{{tabs.multiomics}}</button>
            </div>
            
            <!-- ChIP-seq -->
            <div id="chipseq-tab">
                <div class="form-group">
                    <label>{{labels.analysis_type}}</label>
                    <select id="chipseq-analysis">
                        <option value="macs2">{{chipseq_options.macs2}}</option>
                        <option value="annotation">{{chipseq_options.annotation}}</option>
                        <option value="go">{{chipseq_options.go}}</option>
                        <option value="kegg">{{chipseq_options.kegg}}</option>
                        <option value="motif">{{chipseq_options.motif}}</option>
                        <option value="visualization">{{chipseq_options.visualization}}</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>{{labels.input_file}}</label>
                    <input type="file" id="chipseq-input">
                </div>
                <button class="btn" onclick="runChipSeq()">{{labels.run}}</button>
                <div id="chipseq-result" class="result"></div>
            </div>
            
            <!-- Single Cell -->
            <div id="singlecell-tab" style="display:none;">
                <div class="form-group">
                    <label>{{labels.analysis_type}}</label>
                    <select id="sc-analysis">
                        <option value="dimred">{{sc_options.dimred}}</option>
                        <option value="cluster">{{sc_options.cluster}}</option>
                        <option value="markers">{{sc_options.markers}}</option>
                    </select>
                </div>
                <button class="btn" onclick="runSingleCell()">{{labels.run}}</button>
                <div id="singlecell-result" class="result"></div>
            </div>
            
            <!-- Multi-omics -->
            <div id="multiomics-tab" style="display:none;">
                <div class="form-group">
                    <label>{{labels.analysis_type}}</label>
                    <select id="mo-analysis">
                        <option value="correlation">{{mo_options.correlation}}</option>
                        <option value="network">{{mo_options.network}}</option>
                        <option value="joint">{{mo_options.joint}}</option>
                    </select>
                </div>
                <button class="btn" onclick="runMultiOmics()">{{labels.run}}</button>
                <div id="multiomics-result" class="result"></div>
            </div>
        </div>
    </div>
    
    <script>
        const text = {{text_json | safe}};
        let currentLang = '{{lang}}';
        
        function switchLang() {
            currentLang = currentLang === 'zh' ? 'en' : 'zh';
            location.reload();
        }
        
        function switchTab(tab) {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            event.target.classList.add('active');
            document.getElementById('chipseq-tab').style.display = tab === 'chipseq' ? 'block' : 'none';
            document.getElementById('singlecell-tab').style.display = tab === 'singlecell' ? 'block' : 'none';
            document.getElementById('multiomics-tab').style.display = tab === 'multiomics' ? 'block' : 'none';
        }
        
        function getText() { return text[currentLang]; }
        
        async function runChipSeq() {
            const t = getText();
            const resultDiv = document.getElementById('chipseq-result');
            resultDiv.classList.add('show');
            resultDiv.innerHTML = '<div class="loading">' + t.loading + '</div>';
            
            const analysis = document.getElementById('chipseq-analysis').value;
            
            try {
                const response = await fetch('/api/chipseq', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({analysis})
                });
                const result = await response.json();
                resultDiv.innerHTML = '<pre>' + JSON.stringify(result, null, 2) + '</pre>';
            } catch(e) {
                resultDiv.innerHTML = '<div style="color:red;">Error: ' + e.message + '</div>';
            }
        }
        
        async function runSingleCell() {
            const t = getText();
            const resultDiv = document.getElementById('singlecell-result');
            resultDiv.classList.add('show');
            resultDiv.innerHTML = '<div class="loading">' + t.loading + '</div>';
            
            const analysis = document.getElementById('sc-analysis').value;
            
            try {
                const response = await fetch('/api/singlecell', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({analysis})
                });
                const result = await response.json();
                resultDiv.innerHTML = '<pre>' + JSON.stringify(result, null, 2) + '</pre>';
            } catch(e) {
                resultDiv.innerHTML = '<div style="color:red;">Error: ' + e.message + '</div>';
            }
        }
        
        async function runMultiOmics() {
            const t = getText();
            const resultDiv = document.getElementById('multiomics-result');
            resultDiv.classList.add('show');
            resultDiv.innerHTML = '<div class="loading">' + t.loading + '</div>';
            
            const analysis = document.getElementById('mo-analysis').value;
            
            try {
                const response = await fetch('/api/multiomics', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({analysis})
                });
                const result = await response.json();
                resultDiv.innerHTML = '<pre>' + JSON.stringify(result, null, 2) + '</pre>';
            } catch(e) {
                resultDiv.innerHTML = '<div style="color:red;">Error: ' + e.message + '</div>';
            }
        }
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    lang = request.args.get('lang', 'zh')
    if lang not in ['zh', 'en']:
        lang = 'zh'
    
    return render_template_string(
        HTML_TEMPLATE,
        lang=lang,
        title=TEXT[lang]['title'],
        subtitle=TEXT[lang]['subtitle'],
        features=TEXT[lang]['features'],
        tabs=TEXT[lang]['tabs'],
        labels=TEXT[lang]['labels'],
        chipseq_options=TEXT[lang]['chipseq_options'],
        sc_options=TEXT[lang]['sc_options'],
        mo_options=TEXT[lang]['mo_options'],
        text_json=TEXT
    )

@app.route('/api/chipseq', methods=['POST'])
def api_chipseq():
    data = request.json
    processor = ChipSeqProcessor()
    
    if data['analysis'] == 'macs2':
        result = processor.macs2_call_bam(data.get('input', 'demo.bam'))
    elif data['analysis'] == 'annotation':
        result = processor.annotate_peaks(data.get('input', 'demo.peaks'))
    elif data['analysis'] == 'go':
        result = processor.go_enrichment(data.get('input', 'demo.peaks'))
    elif data['analysis'] == 'kegg':
        result = processor.kegg_enrichment(data.get('input', 'demo.peaks'))
    elif data['analysis'] == 'motif':
        result = processor.motif_analysis(data.get('input', 'demo.peaks'))
    else:
        result = processor.generate_plots()
    
    return jsonify(result)

@app.route('/api/singlecell', methods=['POST'])
def api_singlecell():
    data = request.json
    processor = SingleCellProcessor()
    
    if data['analysis'] == 'dimred':
        result = processor.dimensionality_reduction({}, 'UMAP')
    elif data['analysis'] == 'cluster':
        result = processor.clustering({}, 'Louvain')
    elif data['analysis'] == 'markers':
        result = processor.marker_detection({}, [0,1,2])
    else:
        result = processor.trajectory_analysis({})
    
    return jsonify(result)

@app.route('/api/multiomics', methods=['POST'])
def api_multiomics():
    data = request.json
    processor = MultiOmicsProcessor()
    
    if data['analysis'] == 'correlation':
        result = processor.correlation_analysis({}, {})
    elif data['analysis'] == 'network':
        result = processor.network_integration({}, {}, {})
    else:
        result = processor.joint_analysis({}, {}, {})
    
    return jsonify(result)

if __name__ == '__main__':
    print("""
🧬 EasyMultiProfiler Web (Bilingual)
   
   中文: http://localhost:5000
   English: http://localhost:5000?lang=en
   
   按 Ctrl+C 停止
    """)
    app.run(host='0.0.0.0', port=5000, debug=True)
