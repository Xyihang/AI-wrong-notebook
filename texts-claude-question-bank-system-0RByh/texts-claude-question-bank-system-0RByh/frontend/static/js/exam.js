// 组卷页面逻辑

let availableQuestions = [];
let selectedQuestionsList = [];
let currentPaperId = null;

// 方法切换
document.querySelectorAll('.method-tabs .tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const method = btn.dataset.method;

        document.querySelectorAll('.method-tabs .tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.method-content').forEach(c => c.classList.remove('active'));

        btn.classList.add('active');
        document.getElementById(method + 'Method').classList.add('active');

        if (method === 'view') {
            loadExamPapers();
        }
    });
});

// ========== 手动选题 ==========

// 加载题目供选择
document.getElementById('loadQuestionsBtn').addEventListener('click', async () => {
    const type = document.getElementById('selectorType').value;
    const difficulty = document.getElementById('selectorDifficulty').value;

    try {
        const params = new URLSearchParams();
        if (type) params.append('type', type);
        if (difficulty) params.append('difficulty', difficulty);

        const result = await apiRequest(`/questions?${params.toString()}`);

        if (result.success) {
            availableQuestions = result.questions;
            displayAvailableQuestions();
        }
    } catch (error) {
        showMessage('加载题目失败', 'error');
    }
});

// 显示可选题目
function displayAvailableQuestions() {
    const container = document.getElementById('availableQuestions');
    container.innerHTML = '';

    if (availableQuestions.length === 0) {
        container.innerHTML = '<p>没有找到符合条件的题目</p>';
        return;
    }

    availableQuestions.forEach(q => {
        const div = document.createElement('div');
        div.className = 'question-item';
        div.innerHTML = `
            <input type="checkbox" id="q-${q.id}" data-id="${q.id}">
            <label for="q-${q.id}">
                <strong>[${q.question_type || '未分类'}]</strong> ${truncateText(q.content, 100)}
                <br><small>难度: ${q.difficulty || '-'} | 标签: ${q.tags ? q.tags.join(', ') : '-'}</small>
            </label>
        `;

        div.querySelector('input').addEventListener('change', (e) => {
            const id = parseInt(e.target.dataset.id);
            if (e.target.checked) {
                const question = availableQuestions.find(q => q.id === id);
                if (question) {
                    selectedQuestionsList.push(question);
                    updateSelectedQuestions();
                }
            } else {
                selectedQuestionsList = selectedQuestionsList.filter(q => q.id !== id);
                updateSelectedQuestions();
            }
        });

        container.appendChild(div);
    });
}

// 更新已选题目显示
function updateSelectedQuestions() {
    const container = document.getElementById('selectedQuestionsList');
    const count = document.getElementById('selectedCount');

    count.textContent = selectedQuestionsList.length;
    container.innerHTML = '';

    if (selectedQuestionsList.length === 0) {
        container.innerHTML = '<p>还没有选择题目</p>';
        return;
    }

    selectedQuestionsList.forEach((q, index) => {
        const div = document.createElement('div');
        div.className = 'question-item';
        div.innerHTML = `
            <strong>${index + 1}.</strong> ${truncateText(q.content, 80)}
            <input type="number" placeholder="分数" class="form-control" style="width: 100px; display: inline-block; margin-left: 10px;" data-id="${q.id}" value="5">
            <button class="btn btn-danger btn-sm" onclick="removeQuestion(${q.id})">移除</button>
        `;
        container.appendChild(div);
    });
}

// 移除题目
window.removeQuestion = function(id) {
    selectedQuestionsList = selectedQuestionsList.filter(q => q.id !== id);
    updateSelectedQuestions();

    // 取消选中
    const checkbox = document.querySelector(`#q-${id}`);
    if (checkbox) checkbox.checked = false;
}

// 生成试卷（手动）
document.getElementById('generateManualBtn').addEventListener('click', async () => {
    const name = document.getElementById('manualPaperName').value.trim();
    const paperSize = document.getElementById('manualPaperSize').value;
    const description = document.getElementById('manualDescription').value.trim();

    if (!name) {
        showMessage('请输入试卷名称', 'error');
        return;
    }

    if (selectedQuestionsList.length === 0) {
        showMessage('请至少选择一道题目', 'error');
        return;
    }

    // 获取各题分数
    const scores = [];
    document.querySelectorAll('#selectedQuestionsList input[type="number"]').forEach(input => {
        scores.push(parseFloat(input.value) || 0);
    });

    try {
        const result = await apiRequest('/exam/generate', {
            method: 'POST',
            body: JSON.stringify({
                method: 'selection',
                name,
                paper_size: paperSize,
                description,
                question_ids: selectedQuestionsList.map(q => q.id),
                scores
            })
        });

        if (result.success) {
            showMessage('试卷生成成功！', 'success');
            currentPaperId = result.paper_id;
            previewPaper(result.paper_id);
        }
    } catch (error) {
        showMessage('生成试卷失败: ' + error.message, 'error');
    }
});

// ========== 自动组卷 ==========

document.getElementById('generateAutoBtn').addEventListener('click', async () => {
    const name = document.getElementById('autoPaperName').value.trim();
    const paperSize = document.getElementById('autoPaperSize').value;
    const totalScore = parseFloat(document.getElementById('totalScore').value);
    const questionType = document.getElementById('autoQuestionType').value;
    const difficulty = document.getElementById('autoDifficulty').value;
    const count = parseInt(document.getElementById('questionCount').value);
    const tags = document.getElementById('autoTags').value.split(',').map(t => t.trim()).filter(t => t);

    if (!name) {
        showMessage('请输入试卷名称', 'error');
        return;
    }

    try {
        const result = await apiRequest('/exam/generate', {
            method: 'POST',
            body: JSON.stringify({
                method: 'auto',
                name,
                paper_size: paperSize,
                total_score: totalScore,
                question_type: questionType || undefined,
                difficulty: difficulty || undefined,
                count,
                tags: tags.length > 0 ? tags : undefined
            })
        });

        if (result.success) {
            showMessage('试卷生成成功！', 'success');
            currentPaperId = result.paper_id;
            previewPaper(result.paper_id);
        }
    } catch (error) {
        showMessage('生成试卷失败: ' + error.message, 'error');
    }
});

// ========== 查看试卷 ==========

async function loadExamPapers() {
    try {
        const result = await apiRequest('/exam/papers');

        if (result.success) {
            displayPapersList(result.papers);
        }
    } catch (error) {
        showMessage('加载试卷列表失败', 'error');
    }
}

function displayPapersList(papers) {
    const container = document.getElementById('papersList');
    container.innerHTML = '';

    if (papers.length === 0) {
        container.innerHTML = '<p>还没有创建试卷</p>';
        return;
    }

    const table = document.createElement('table');
    table.className = 'data-table';
    table.innerHTML = `
        <thead>
            <tr>
                <th>ID</th>
                <th>试卷名称</th>
                <th>尺寸</th>
                <th>总分</th>
                <th>题目数</th>
                <th>创建时间</th>
                <th>操作</th>
            </tr>
        </thead>
        <tbody></tbody>
    `;

    const tbody = table.querySelector('tbody');
    papers.forEach(paper => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td>${paper.id}</td>
            <td>${paper.name}</td>
            <td>${paper.paper_size}</td>
            <td>${paper.total_score}</td>
            <td>${paper.question_count}</td>
            <td>${formatDate(paper.created_at)}</td>
            <td>
                <button class="btn btn-primary btn-sm" onclick="previewPaper(${paper.id})">预览</button>
                <button class="btn btn-danger btn-sm" onclick="deletePaper(${paper.id})">删除</button>
            </td>
        `;
        tbody.appendChild(tr);
    });

    container.appendChild(table);
}

// 预览试卷
window.previewPaper = async function(paperId) {
    try {
        const result = await apiRequest(`/exam/papers/${paperId}`);

        if (result.success) {
            currentPaperId = paperId;
            const paper = result.paper;

            document.getElementById('previewTitle').textContent = paper.name;

            let html = `
                <div style="padding: 1rem;">
                    <h4>${paper.name}</h4>
                    <p>总分: ${paper.total_score} | 题目数: ${paper.question_count} | 尺寸: ${paper.paper_size}</p>
                    ${paper.description ? `<p>说明: ${paper.description}</p>` : ''}
                    <hr>
            `;

            paper.questions.forEach((q, index) => {
                html += `
                    <div style="margin: 1rem 0; padding: 1rem; background: #f8f9fa; border-radius: 5px;">
                        <p><strong>${index + 1}. [${q.question_type}] (${q.score}分)</strong></p>
                        <p>${q.content}</p>
                        <p style="color: #7f8c8d;"><small>难度: ${q.difficulty} | 标签: ${q.tags.join(', ')}</small></p>
                    </div>
                `;
            });

            html += '</div>';

            document.getElementById('previewContent').innerHTML = html;
            showModal('previewModal');
        }
    } catch (error) {
        showMessage('加载试卷失败', 'error');
    }
}

// 删除试卷
window.deletePaper = async function(paperId) {
    if (!confirm('确定要删除这份试卷吗？')) return;

    try {
        const result = await apiRequest(`/exam/papers/${paperId}`, { method: 'DELETE' });
        if (result.success) {
            showMessage('删除成功', 'success');
            loadExamPapers();
        }
    } catch (error) {
        showMessage('删除失败', 'error');
    }
}

// 导出试卷
document.getElementById('exportWithAnswersBtn').addEventListener('click', () => {
    exportPaper(true);
});

document.getElementById('exportNoAnswersBtn').addEventListener('click', () => {
    exportPaper(false);
});

async function exportPaper(withAnswers) {
    if (!currentPaperId) return;

    try {
        const url = `/api/exam/export/${currentPaperId}?answers=${withAnswers}&analysis=false`;
        const response = await fetch(url);

        if (response.ok) {
            const blob = await response.blob();
            const downloadUrl = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = downloadUrl;
            a.download = `试卷_${currentPaperId}.docx`;
            a.click();
            showMessage('导出成功', 'success');
        }
    } catch (error) {
        showMessage('导出失败', 'error');
    }
}

// 关闭预览
document.getElementById('closePreviewBtn').addEventListener('click', () => {
    hideModal('previewModal');
});
