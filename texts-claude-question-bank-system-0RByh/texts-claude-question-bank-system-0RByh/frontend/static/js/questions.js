// 题目管理页面逻辑

let allQuestions = [];
let selectedQuestions = new Set();

// 加载题目列表
async function loadQuestions(filters = {}) {
    try {
        const params = new URLSearchParams();
        if (filters.keyword) params.append('keyword', filters.keyword);
        if (filters.type) params.append('type', filters.type);
        if (filters.difficulty) params.append('difficulty', filters.difficulty);
        if (filters.tags && filters.tags.length > 0) {
            filters.tags.forEach(tag => params.append('tags', tag));
        }

        const result = await apiRequest(`/questions?${params.toString()}`);

        if (result.success) {
            allQuestions = result.questions;
            displayQuestions(allQuestions);
        }
    } catch (error) {
        showMessage('加载题目失败: ' + error.message, 'error');
    }
}

// 显示题目列表
function displayQuestions(questions) {
    const tbody = document.getElementById('questionsBody');
    tbody.innerHTML = '';

    if (questions.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center">暂无题目</td></tr>';
        return;
    }

    questions.forEach(question => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td><input type="checkbox" class="question-checkbox" data-id="${question.id}"></td>
            <td>${question.id}</td>
            <td>${truncateText(question.content, 80)}</td>
            <td>${question.question_type || '-'}</td>
            <td>${question.difficulty || '-'}</td>
            <td>${question.tags ? question.tags.map(t => `<span class="tag">${t}</span>`).join('') : '-'}</td>
            <td>
                <button class="btn btn-primary btn-sm" onclick="viewQuestion(${question.id})">查看</button>
                <button class="btn btn-secondary btn-sm" onclick="editQuestion(${question.id})">编辑</button>
                <button class="btn btn-danger btn-sm" onclick="deleteQuestion(${question.id})">删除</button>
            </td>
        `;
        tbody.appendChild(tr);
    });

    // 添加复选框事件
    document.querySelectorAll('.question-checkbox').forEach(checkbox => {
        checkbox.addEventListener('change', (e) => {
            const id = parseInt(e.target.dataset.id);
            if (e.target.checked) {
                selectedQuestions.add(id);
            } else {
                selectedQuestions.delete(id);
            }
        });
    });
}

// 搜索题目
document.getElementById('searchBtn').addEventListener('click', () => {
    const keyword = document.getElementById('searchKeyword').value.trim();
    const type = document.getElementById('filterType').value;
    const difficulty = document.getElementById('filterDifficulty').value;

    loadQuestions({ keyword, type, difficulty });
});

// 全选/取消全选
document.getElementById('selectAll').addEventListener('change', (e) => {
    const checkboxes = document.querySelectorAll('.question-checkbox');
    checkboxes.forEach(checkbox => {
        checkbox.checked = e.target.checked;
        const id = parseInt(checkbox.dataset.id);
        if (e.target.checked) {
            selectedQuestions.add(id);
        } else {
            selectedQuestions.delete(id);
        }
    });
});

// 新建题目
document.getElementById('addQuestionBtn').addEventListener('click', () => {
    document.getElementById('modalTitle').textContent = '新建题目';
    document.getElementById('questionForm').reset();
    document.getElementById('questionId').value = '';
    showModal('questionModal');
});

// 查看题目
window.viewQuestion = async function(id) {
    try {
        const result = await apiRequest(`/questions/${id}`);
        if (result.success) {
            const q = result.question;
            alert(`题目内容：\n${q.content}\n\n答案：\n${q.answer || '无'}\n\n解析：\n${q.analysis || '无'}`);
        }
    } catch (error) {
        showMessage('加载题目失败', 'error');
    }
}

// 编辑题目
window.editQuestion = async function(id) {
    try {
        const result = await apiRequest(`/questions/${id}`);
        if (result.success) {
            const q = result.question;
            document.getElementById('modalTitle').textContent = '编辑题目';
            document.getElementById('questionId').value = q.id;
            document.getElementById('content').value = q.content;
            document.getElementById('questionType').value = q.question_type || '';
            document.getElementById('difficulty').value = q.difficulty || '';
            document.getElementById('tags').value = q.tags ? q.tags.map(t => t.name).join(', ') : '';
            document.getElementById('answer').value = q.answer || '';
            document.getElementById('analysis').value = q.analysis || '';
            document.getElementById('source').value = q.source || '';
            showModal('questionModal');
        }
    } catch (error) {
        showMessage('加载题目失败', 'error');
    }
}

// 删除题目
window.deleteQuestion = async function(id) {
    if (!confirm('确定要删除这道题目吗？')) return;

    try {
        const result = await apiRequest(`/questions/${id}`, { method: 'DELETE' });
        if (result.success) {
            showMessage('删除成功', 'success');
            loadQuestions();
        }
    } catch (error) {
        showMessage('删除失败', 'error');
    }
}

// 保存题目表单
document.getElementById('questionForm').addEventListener('submit', async (e) => {
    e.preventDefault();

    const id = document.getElementById('questionId').value;
    const data = {
        content: document.getElementById('content').value,
        question_type: document.getElementById('questionType').value,
        difficulty: document.getElementById('difficulty').value,
        tags: document.getElementById('tags').value.split(',').map(t => t.trim()).filter(t => t),
        answer: document.getElementById('answer').value,
        analysis: document.getElementById('analysis').value,
        source: document.getElementById('source').value
    };

    try {
        let result;
        if (id) {
            result = await apiRequest(`/questions/${id}`, {
                method: 'PUT',
                body: JSON.stringify(data)
            });
        } else {
            result = await apiRequest('/questions', {
                method: 'POST',
                body: JSON.stringify(data)
            });
        }

        if (result.success) {
            showMessage(id ? '更新成功' : '创建成功', 'success');
            hideModal('questionModal');
            loadQuestions();
        }
    } catch (error) {
        showMessage('保存失败', 'error');
    }
});

// 关闭模态框
document.getElementById('closeModalBtn').addEventListener('click', () => {
    hideModal('questionModal');
});

// 导出选中题目
document.getElementById('exportSelectedBtn').addEventListener('click', async () => {
    if (selectedQuestions.size === 0) {
        showMessage('请先选择要导出的题目', 'error');
        return;
    }

    try {
        const response = await fetch('/api/questions/export', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                question_ids: Array.from(selectedQuestions),
                title: '导出题库'
            })
        });

        if (response.ok) {
            const blob = await response.blob();
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = '题库导出.docx';
            a.click();
            showMessage('导出成功', 'success');
        }
    } catch (error) {
        showMessage('导出失败', 'error');
    }
});

// 初始加载
loadQuestions();
