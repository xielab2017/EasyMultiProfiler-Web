#!/usr/bin/env python3
"""
EasyMultiProfiler Web Application
Flask网页应用
"""

from flask import Flask, render_template_string, request, jsonify
import sys
import os

# 添加processors路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from processors import ChipSeqProcessor, SingleCellProcessor, MultiOmicsProcessor

app = Flask(__name__)

# HTML模板
HTML = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EasyMultiProfiler Web</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
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
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>🧬 EasyMultiProfiler Web</h1>
            <p class="subtitle">零门槛多组学分析平台</p>
            
            <div class="features">
                <div class="feature-card">
                    <h3>🧬 ChIP-seq</h3>
                    <p>Peak calling, Motif分析</p>
                </div>
                <div class="feature-card">
                    <h3>🦠 单细胞</h3>
                    <p>降维, 聚类, 标记基因</p>
                </div>
                <div class="feature-card">
                    <h3>🧪 多组学</h3>
                    <p>RNA-seq + 微生物组整合</p>
                </div>
            </div>
            
            <div class="tab-nav">
                <button class="tab-btn active" onclick="switchTab('chipseq')">🧬 ChIP-seq</button>
                <button class="tab-btn" onclick="switchTab('singlecell')">🦠 单细胞</button>
                <button class="tab-btn" onclick="switchTab('multiomics')">🧪 多组学</button>
            </div>
            
            <!-- ChIP-seq -->
            <div id="chipseq-tab">
                <div class="form-group">
                    <label>分析类型</label>
                    <select id="chipseq-analysis">
                        <option value="qc">质控 (QC)</option>
                        <option value="callpeak">Peak Calling</option>
                        <option value="motif">Motif分析</option>
                        <option value="annotate">Peak注释</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>输入文件 (BAM/BED)</label>
                    <input type="file" id="chipseq-input">
                </div>
                <button class="btn" onclick="runChipSeq()">🚀 开始分析</button>
                <div id="chipseq-result" class="result"></div>
            </div>
            
            <!-- 单细胞 -->
            <div id="singlecell-tab" style="display:none;">
                <div class="form-group">
                    <label>分析类型</label>
                    <select id="sc-analysis">
                        <option value="dimred">降维 (UMAP/tSNE)</option>
                        <option value="cluster">聚类分析</option>
                        <option value="markers">标记基因检测</option>
                        <option value="trajectory">轨迹分析</option>
                    </select>
                </div>
                <button class="btn" onclick="runSingleCell()">🚀 开始分析</button>
                <div id="singlecell-result" class="result"></div>
            </div>
            
            <!-- 多组学 -->
            <div id="multiomics-tab" style="display:none;">
                <div class="form-group">
                    <label>组学类型</label>
                    <select id="mo-analysis">
                        <option value="correlation">相关性分析</option>
                        <option value="network">网络整合</option>
                        <option value="joint">联合分析</option>
                    </select>
                </div>
                <button class="btn" onclick="runMultiOmics()">🚀 开始分析</button>
                <div id="multiomics-result" class="result"></div>
            </div>
        </div>
    </div>
    
    <script>
        function switchTab(tab) {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            event.target.classList.add('active');
            document.getElementById('chipseq-tab').style.display = tab === 'chipseq' ? 'block' : 'none';
            document.getElementById('singlecell-tab').style.display = tab === 'singlecell' ? 'block' : 'none';
            document.getElementById('multiomics-tab').style.display = tab === 'multiomics' ? 'block' : 'none';
        }
        
        async function runChipSeq() {
            const resultDiv = document.getElementById('chipseq-result');
            resultDiv.classList.add('show');
            resultDiv.innerHTML = '<div class="loading">🧬 分析中...</div>';
            
            const analysis = document.getElementById('chipseq-analysis').value;
            
            try {
                const response = await fetch('/api/chipseq', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({analysis, input: 'demo.bam'})
                });
                const result = await response.json();
                resultDiv.innerHTML = '<pre>' + JSON.stringify(result, null, 2) + '</pre>';
            } catch(e) {
                resultDiv.innerHTML = '<div style="color:red;">错误: ' + e.message + '</div>';
            }
        }
        
        async function runSingleCell() {
            const resultDiv = document.getElementById('singlecell-result');
            resultDiv.classList.add('show');
            resultDiv.innerHTML = '<div class="loading">🦠 分析中...</div>';
            
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
                resultDiv.innerHTML = '<div style="color:red;">错误: ' + e.message + '</div>';
            }
        }
        
        async function runMultiOmics() {
            const resultDiv = document.getElementById('multiomics-result');
            resultDiv.classList.add('show');
            resultDiv.innerHTML = '<div class="loading">🧪 分析中...</div>';
            
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
                resultDiv.innerHTML = '<div style="color:red;">错误: ' + e.message + '</div>';
            }
        }
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/api/chipseq', methods=['POST'])
def api_chipseq():
    data = request.json
    processor = ChipSeqProcessor()
    
    if data['analysis'] == 'qc':
        result = processor.quality_control(data.get('input', 'demo.bam'))
    elif data['analysis'] == 'motif':
        result = processor.motif_analysis(data.get('input', 'demo.peaks'))
    elif data['analysis'] == 'annotate':
        result = processor.annotation(data.get('input', 'demo.peaks'))
    else:
        result = processor.peak_calling(data.get('input', 'demo.bam'))
    
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
🧬 EasyMultiProfiler Web 启动中...
   
   访问: http://localhost:5000
   
   按 Ctrl+C 停止
    """)
    app.run(host='0.0.0.0', port=5000, debug=True)
