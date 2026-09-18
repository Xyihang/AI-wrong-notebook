// 试卷模板管理逻辑

let currentTemplateId = null;
let allTemplates = [];

// 页面加载时获取模板列表
document.addEventListener('DOMContentLoaded', () => {
    loadTemplates();
});

// 加载模板列表
async function loadTemplates(category = null) {
    try {
        const url = category ? `/api/templates?category=${encodeURIComponent(category)}` : '/api/templates';
        const response = await fetch(url);
        const result = await response.json();

        if (result.success) {
            allTemplates = result.templates;
            displayTemplates(allTemplates);
        } else {
            showMessage('加载模板失败: ' + result.error, 'error');
        }
    } catch (error) {
        showMessage('加载模板失败: ' + error.message, 'error');
    }
}

// 显示模板列表
function displayTemplates(templates) {
    const list = document.getElementById('templatesList');
    list.innerHTML = '';

    if (templates.length === 0) {
        list.innerHTML = '<p class="empty-message">暂无模板</p>';
        return;
    }

    templates.forEach(template => {
        const card = document.createElement('div');
        card.className = 'template-card';
        if (template.is_system) {
            card.classList.add('system-template');
        }

        const structure = template.structure || {};
        const sections = structure.sections || [];

        card.innerHTML = `
            <div class="template-header">
                <h4>${template.name}</h4>
                ${template.is_system ? '<span class="badge badge-system">系统预设</span>' : '<span class="badge badge-custom">自定义</span>'}
            </div>
            <div class="template-body">
                <p class="template-description">${template.description || '暂无描述'}</p>
                <div class="template-info">
                    <div class="info-item">
                        <span class="label">类别：</span>
                        <span>${template.category || '未分类'}</span>
                    </div>
                    <div class="info-item">
                        <span class="label">总分：</span>
                        <span>${template.total_score}分</span>
                    </div>
                    <div class="info-item">
                        <span class="label">试卷尺寸：</span>
                        <span>${template.paper_size}</span>
                    </div>
                    <div class="info-item">
                        <span class="label">题型数量：</span>
                        <span>${sections.length}个大题</span>
                    </div>
                </div>
            </div>
            <div class="template-footer">
                <button class="btn btn-primary btn-sm" onclick="viewTemplate(${template.id})">查看详情</button>
                <button class="btn btn-success btn-sm" onclick="useTemplate(${template.id})">使用模板</button>
            </div>
        `;

        list.appendChild(card);
    });
}

// 查看模板详情
function viewTemplate(templateId) {
    const template = allTemplates.find(t => t.id === templateId);
    if (!template) return;

    currentTemplateId = templateId;

    const modal = document.getElementById('templateModal');
    const details = document.getElementById('templateDetails');
    const title = document.getElementById('modalTitle');

    title.textContent = template.name;

    const structure = template.structure || {};
    const header = structure.header || {};
    const sections = structure.sections || [];

    let sectionsHtml = '';
    sections.forEach((section, index) => {
        sectionsHtml += `
            <div class="section-card">
                <h5>${section.title || `第${index + 1}部分`}</h5>
                <div class="section-details">
                    <p><strong>题型：</strong>${section.type}</p>
                    <p><strong>题目数量：</strong>${section.count}题</p>
                    <p><strong>每题分值：</strong>${section.score_per_item}分</p>
                    <p><strong>小计：</strong>${section.total_score}分</p>
                    ${section.description ? `<p><strong>说明：</strong>${section.description}</p>` : ''}
                    ${section.difficulty ? `<p><strong>难度分布：</strong>${JSON.stringify(section.difficulty)}</p>` : ''}
                </div>
            </div>
        `;
    });

    details.innerHTML = `
        <div class="template-full-details">
            <div class="header-section">
                <h4>试卷头部信息</h4>
                <p><strong>标题：</strong>${header.title || '未设置'}</p>
                <p><strong>副标题：</strong>${header.subtitle || '未设置'}</p>
                ${header.instructions ? `<p><strong>考试说明：</strong><br>${header.instructions.replace(/\n/g, '<br>')}</p>` : ''}
            </div>
            <div class="sections-container">
                <h4>试卷结构</h4>
                ${sectionsHtml}
            </div>
            <div class="summary-section">
                <h4>总体信息</h4>
                <p><strong>总题数：</strong>${sections.reduce((sum, s) => sum + s.count, 0)}题</p>
                <p><strong>总分：</strong>${template.total_score}分</p>
                <p><strong>试卷尺寸：</strong>${template.paper_size}</p>
            </div>
        </div>
    `;

    showModal('templateModal');
}

// 使用模板生成试卷
function useTemplate(templateId) {
    currentTemplateId = templateId;
    const template = allTemplates.find(t => t.id === templateId);

    if (template) {
        document.getElementById('paperName').value = template.name + ' - ' + new Date().toLocaleDateString();
    }

    hideModal('templateModal');
    showModal('generateModal');
}

// 查看统计
document.getElementById('viewStatsBtn').addEventListener('click', async () => {
    if (!currentTemplateId) return;

    try {
        const response = await fetch(`/api/templates/${currentTemplateId}/stats`);
        const result = await response.json();

        if (result.success) {
            const stats = result.statistics;
            const content = document.getElementById('statsContent');

            let typesHtml = '';
            for (const [type, info] of Object.entries(stats.question_types || {})) {
                typesHtml += `
                    <tr>
                        <td>${type}</td>
                        <td>${info.count}</td>
                        <td>${info.total_score}分</td>
                    </tr>
                `;
            }

            content.innerHTML = `
                <div class="stats-grid">
                    <div class="stat-card">
                        <div class="stat-value">${stats.total_questions}</div>
                        <div class="stat-label">总题数</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value">${stats.total_score}分</div>
                        <div class="stat-label">总分</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value">${stats.sections_count}</div>
                        <div class="stat-label">大题数</div>
                    </div>
                </div>

                <h4>题型分布</h4>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>题型</th>
                            <th>题目数量</th>
                            <th>分值</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${typesHtml}
                    </tbody>
                </table>

                <h4>难度分布</h4>
                <div class="difficulty-chart">
                    <div class="difficulty-bar">
                        <span>简单：${stats.difficulty_distribution['简单']}题</span>
                        <div class="bar" style="width: ${stats.difficulty_distribution['简单'] / stats.total_questions * 100}%; background: #27ae60;"></div>
                    </div>
                    <div class="difficulty-bar">
                        <span>中等：${stats.difficulty_distribution['中等']}题</span>
                        <div class="bar" style="width: ${stats.difficulty_distribution['中等'] / stats.total_questions * 100}%; background: #f39c12;"></div>
                    </div>
                    <div class="difficulty-bar">
                        <span>困难：${stats.difficulty_distribution['困难']}题</span>
                        <div class="bar" style="width: ${stats.difficulty_distribution['困难'] / stats.total_questions * 100}%; background: #e74c3c;"></div>
                    </div>
                </div>
            `;

            hideModal('templateModal');
            showModal('statsModal');
        }
    } catch (error) {
        showMessage('获取统计信息失败: ' + error.message, 'error');
    }
});

// 确认生成试卷
document.getElementById('confirmGenerateBtn').addEventListener('click', async () => {
    const paperName = document.getElementById('paperName').value.trim();

    if (!paperName) {
        showMessage('请输入试卷名称', 'error');
        return;
    }

    if (!currentTemplateId) {
        showMessage('未选择模板', 'error');
        return;
    }

    try {
        const response = await fetch(`/api/templates/${currentTemplateId}/generate`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ name: paperName })
        });

        const result = await response.json();

        if (result.success) {
            showMessage('试卷生成成功！', 'success');
            hideModal('generateModal');

            // 跳转到试卷页面
            setTimeout(() => {
                window.location.href = '/exam';
            }, 1500);
        } else {
            showMessage('生成失败: ' + result.error, 'error');
        }
    } catch (error) {
        showMessage('生成失败: ' + error.message, 'error');
    }
});

// 筛选按钮
document.getElementById('filterBtn').addEventListener('click', () => {
    const category = document.getElementById('categoryFilter').value;
    loadTemplates(category || null);
});

// 关闭按钮
document.getElementById('closeModalBtn').addEventListener('click', () => {
    hideModal('templateModal');
});

document.getElementById('cancelGenerateBtn').addEventListener('click', () => {
    hideModal('generateModal');
});

document.getElementById('closeStatsBtn').addEventListener('click', () => {
    hideModal('statsModal');
});

// 工具函数
function showModal(modalId) {
    document.getElementById(modalId).style.display = 'block';
}

function hideModal(modalId) {
    document.getElementById(modalId).style.display = 'none';
}

function showMessage(message, type) {
    // 简单的消息提示（可以用更好的UI组件替换）
    alert(message);
}
