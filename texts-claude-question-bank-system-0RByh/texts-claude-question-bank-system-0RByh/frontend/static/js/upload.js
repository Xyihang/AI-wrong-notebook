// 上传页面逻辑

let extractedQuestions = [];
let currentFilename = '';
let aiAvailable = false;
let originalOcrText = '';

// 检查AI状态
async function checkAIStatus() {
    try {
        const response = await fetch('/api/ai/status');
        const result = await response.json();
        aiAvailable = result.available;

        const statusBar = document.getElementById('aiStatusBar');
        const statusText = document.getElementById('aiStatusText');
        const toggle = document.getElementById('useAiToggle');

        if (aiAvailable) {
            statusText.innerHTML = '✅ AI助手已启用 - 将自动纠正OCR识别结果';
            statusBar.style.backgroundColor = '#d4edda';
            statusBar.style.color = '#155724';
            toggle.disabled = false;
        } else {
            statusText.innerHTML = '⚠️ AI助手未配置 - 将使用基础OCR识别';
            statusBar.style.backgroundColor = '#fff3cd';
            statusBar.style.color = '#856404';
            toggle.checked = false;
            toggle.disabled = true;
        }
    } catch (error) {
        console.error('检查AI状态失败:', error);
    }
}

// 页面加载时检查AI状态
checkAIStatus();

// 上传区域
const uploadArea = document.getElementById('uploadArea');
const fileInput = document.getElementById('fileInput');

uploadArea.addEventListener('click', () => fileInput.click());

// 拖拽上传
uploadArea.addEventListener('dragover', (e) => {
    e.preventDefault();
    uploadArea.style.borderColor = '#2980b9';
    uploadArea.style.backgroundColor = '#ecf0f1';
});

uploadArea.addEventListener('dragleave', () => {
    uploadArea.style.borderColor = '#3498db';
    uploadArea.style.backgroundColor = 'white';
});

uploadArea.addEventListener('drop', (e) => {
    e.preventDefault();
    uploadArea.style.borderColor = '#3498db';
    uploadArea.style.backgroundColor = 'white';

    const files = e.dataTransfer.files;
    if (files.length > 0) {
        handleFileUpload(files[0]);
    }
});

fileInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
        handleFileUpload(e.target.files[0]);
    }
});

// 处理文件上传
async function handleFileUpload(file) {
    const formData = new FormData();
    formData.append('file', file);

    // 添加AI使用选项
    const useAi = document.getElementById('useAiToggle').checked;
    formData.append('use_ai', useAi);

    const processingStatus = document.getElementById('processingStatus');
    processingStatus.style.display = 'block';
    processingStatus.querySelector('p').textContent = useAi ?
        '正在识别文本并使用AI纠正，请稍候...' : '正在识别文本，请稍候...';

    document.getElementById('resultSection').style.display = 'none';

    try {
        const response = await fetch('/api/upload', {
            method: 'POST',
            body: formData
        });

        const result = await response.json();

        if (result.success) {
            currentFilename = result.filename;
            extractedQuestions = result.questions || [];
            originalOcrText = result.original_text || result.text;

            // 显示识别文本
            document.getElementById('extractedText').value = result.text;

            // 如果使用了AI且有原始文本，显示对比
            if (result.ai_used && result.original_text !== result.text) {
                document.getElementById('originalText').value = result.original_text;
                document.getElementById('originalTab').style.display = 'block';

                // 显示AI纠正信息
                displayAICorrectionInfo(result);
            } else {
                document.getElementById('originalTab').style.display = 'none';
                document.getElementById('aiCorrectionInfo').style.display = 'none';
            }

            // 显示提取的题目
            displayExtractedQuestions(extractedQuestions, result.ai_used);

            document.getElementById('processingStatus').style.display = 'none';
            document.getElementById('resultSection').style.display = 'block';

            const message = result.ai_used ?
                `文件识别成功！AI已纠正文本并提取 ${extractedQuestions.length} 道题目` :
                `文件识别成功！提取 ${extractedQuestions.length} 道题目`;
            showMessage(message, 'success');
        } else {
            throw new Error(result.error || '识别失败');
        }
    } catch (error) {
        document.getElementById('processingStatus').style.display = 'none';
        showMessage('文件识别失败: ' + error.message, 'error');
    }
}

// 显示AI纠正信息
function displayAICorrectionInfo(result) {
    const infoBox = document.getElementById('aiCorrectionInfo');
    const ocrConf = document.getElementById('ocrConfidence');
    const aiConf = document.getElementById('aiConfidence');
    const correctionsList = document.getElementById('correctionsItems');

    if (result.ai_correction) {
        infoBox.style.display = 'block';

        // 显示置信度
        ocrConf.textContent = `${(result.ocr_confidence * 100).toFixed(1)}%`;
        ocrConf.className = result.ocr_confidence > 0.9 ? 'confidence-high' :
                           result.ocr_confidence > 0.7 ? 'confidence-medium' : 'confidence-low';

        const aiConfText = result.ai_correction.confidence || 'unknown';
        aiConf.textContent = aiConfText;
        aiConf.className = aiConfText === 'high' ? 'confidence-high' :
                          aiConfText === 'medium' ? 'confidence-medium' : 'confidence-low';

        // 显示纠正列表
        correctionsList.innerHTML = '';
        const corrections = result.ai_correction.corrections || [];
        if (corrections.length > 0) {
            corrections.forEach(correction => {
                const li = document.createElement('li');
                li.textContent = correction;
                correctionsList.appendChild(li);
            });
        } else {
            correctionsList.innerHTML = '<li>未发现明显错误</li>';
        }
    } else {
        infoBox.style.display = 'none';
    }
}

// 显示提取的题目
function displayExtractedQuestions(questions, aiUsed = false) {
    const list = document.getElementById('questionsList');
    list.innerHTML = '';

    if (questions.length === 0) {
        list.innerHTML = '<p>未能自动提取题目，请在识别文本中手动复制题目内容</p>';
        return;
    }

    // 如果是AI提取的题目，显示更详细的信息
    if (aiUsed && questions[0] && typeof questions[0] === 'object') {
        questions.forEach((q, index) => {
            const div = document.createElement('div');
            div.className = 'question-item ai-parsed';

            let choicesHtml = '';
            if (q.choices && q.choices.length > 0) {
                choicesHtml = '<div class="choices">' + q.choices.join('<br>') + '</div>';
            }

            let tagsHtml = '';
            if (q.tags && q.tags.length > 0) {
                tagsHtml = '<div class="tags-display">' +
                    q.tags.map(t => `<span class="tag">${t}</span>`).join('') +
                    '</div>';
            }

            div.innerHTML = `
                <div class="question-header">
                    <strong>题目 ${q.question_number || index + 1}</strong>
                    <span class="badge badge-type">${q.question_type || '未知'}</span>
                    <span class="badge badge-difficulty">${q.difficulty || '未知'}</span>
                </div>
                <p class="question-content">${q.content}</p>
                ${choicesHtml}
                ${tagsHtml}
                ${q.notes ? `<p class="notes"><small>📝 ${q.notes}</small></p>` : ''}
                <button class="btn btn-primary btn-sm" onclick="saveAIQuestion(${index})">保存此题</button>
            `;
            list.appendChild(div);
        });
    } else {
        // 基础题目显示
        questions.forEach((question, index) => {
            const questionText = typeof question === 'string' ? question : question.content;
            const div = document.createElement('div');
            div.className = 'question-item';
            div.innerHTML = `
                <strong>题目 ${index + 1}:</strong>
                <p>${questionText}</p>
                <button class="btn btn-primary btn-sm" onclick="saveQuestion(${index})">保存此题</button>
            `;
            list.appendChild(div);
        });
    }
}

// 保存AI解析的题目
window.saveAIQuestion = function(index) {
    const question = extractedQuestions[index];
    if (typeof question === 'object') {
        // 预填充AI解析的信息
        document.getElementById('extractedText').value = question.content;
        document.getElementById('questionType').value = translateQuestionType(question.question_type);
        document.getElementById('difficulty').value = translateDifficulty(question.difficulty);
        document.getElementById('tags').value = question.tags ? question.tags.join(', ') : '';

        showModal('saveModal');
    } else {
        saveQuestion(index);
    }
}

// 翻译题型
function translateQuestionType(type) {
    const typeMap = {
        'multiple_choice': '选择题',
        'true_false': '判断题',
        'short_answer': '解答题',
        'essay': '解答题',
        'fill_in_blank': '填空题',
        'calculation': '计算题'
    };
    return typeMap[type] || '选择题';
}

// 翻译难度
function translateDifficulty(difficulty) {
    const diffMap = {
        'easy': '简单',
        'medium': '中等',
        'hard': '困难'
    };
    return diffMap[difficulty] || '中等';
}

// 标签页切换
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const tab = btn.dataset.tab;

        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));

        btn.classList.add('active');
        document.getElementById(tab + 'Tab').classList.add('active');
    });
});

// 保存单个题目
window.saveQuestion = function(index) {
    const question = extractedQuestions[index];
    document.getElementById('extractedText').value = question;
    showModal('saveModal');
}

// 保存所有题目
document.getElementById('saveQuestionsBtn').addEventListener('click', () => {
    const text = document.getElementById('extractedText').value.trim();
    if (!text) {
        showMessage('没有可保存的内容', 'error');
        return;
    }
    showModal('saveModal');
});

// 确认保存
document.getElementById('confirmSaveBtn').addEventListener('click', async () => {
    const content = document.getElementById('extractedText').value.trim();
    const questionType = document.getElementById('questionType').value;
    const difficulty = document.getElementById('difficulty').value;
    const tags = document.getElementById('tags').value.split(',').map(t => t.trim()).filter(t => t);
    const answer = document.getElementById('answer').value.trim();

    if (!content) {
        showMessage('题目内容不能为空', 'error');
        return;
    }

    try {
        const result = await apiRequest('/questions', {
            method: 'POST',
            body: JSON.stringify({
                content,
                question_type: questionType,
                difficulty,
                tags,
                answer,
                source: currentFilename
            })
        });

        if (result.success) {
            showMessage('题目保存成功！', 'success');
            hideModal('saveModal');

            // 清空表单
            document.getElementById('tags').value = '';
            document.getElementById('answer').value = '';
        } else {
            throw new Error(result.error || '保存失败');
        }
    } catch (error) {
        showMessage('保存失败: ' + error.message, 'error');
    }
});

// 取消保存
document.getElementById('cancelSaveBtn').addEventListener('click', () => {
    hideModal('saveModal');
});

// 清空并重新上传
document.getElementById('clearBtn').addEventListener('click', () => {
    document.getElementById('resultSection').style.display = 'none';
    document.getElementById('extractedText').value = '';
    extractedQuestions = [];
    currentFilename = '';
    fileInput.value = '';
});
