"""
试卷模板管理器
"""
from typing import List, Dict, Any, Optional
from sqlalchemy.orm import Session
from backend.database.models import ExamTemplate, ExamPaper
from backend.templates.english_templates import PRESET_TEMPLATES, get_all_templates, get_template_by_name
import json


class TemplateManager:
    """试卷模板管理"""

    def __init__(self, db_manager):
        """初始化"""
        self.db_manager = db_manager

    def init_preset_templates(self):
        """初始化预设模板到数据库"""
        session = self.db_manager.get_session()
        try:
            for template_data in PRESET_TEMPLATES:
                # 检查模板是否已存在
                existing = session.query(ExamTemplate).filter_by(
                    name=template_data['name'],
                    is_system=True
                ).first()

                if not existing:
                    template = ExamTemplate(
                        name=template_data['name'],
                        description=template_data['description'],
                        category=template_data['category'],
                        total_score=template_data['total_score'],
                        paper_size=template_data['paper_size'],
                        is_system=True
                    )
                    template.set_structure(template_data['structure'])
                    session.add(template)

            session.commit()
            return True
        except Exception as e:
            session.rollback()
            print(f"初始化预设模板失败: {e}")
            return False
        finally:
            session.close()

    def get_all_templates(self, category: Optional[str] = None) -> List[Dict]:
        """获取所有模板"""
        session = self.db_manager.get_session()
        try:
            query = session.query(ExamTemplate)
            if category:
                query = query.filter_by(category=category)

            templates = query.order_by(ExamTemplate.created_at.desc()).all()

            result = []
            for template in templates:
                result.append({
                    'id': template.id,
                    'name': template.name,
                    'description': template.description,
                    'category': template.category,
                    'total_score': template.total_score,
                    'paper_size': template.paper_size,
                    'is_system': template.is_system,
                    'structure': template.get_structure(),
                    'created_at': template.created_at.isoformat() if template.created_at else None
                })

            return result
        finally:
            session.close()

    def get_template(self, template_id: int) -> Optional[Dict]:
        """获取单个模板"""
        session = self.db_manager.get_session()
        try:
            template = session.query(ExamTemplate).filter_by(id=template_id).first()
            if template:
                return {
                    'id': template.id,
                    'name': template.name,
                    'description': template.description,
                    'category': template.category,
                    'total_score': template.total_score,
                    'paper_size': template.paper_size,
                    'is_system': template.is_system,
                    'structure': template.get_structure(),
                    'created_at': template.created_at.isoformat() if template.created_at else None
                }
            return None
        finally:
            session.close()

    def create_template(self, name: str, description: str, category: str,
                       total_score: float, paper_size: str, structure: Dict) -> int:
        """创建自定义模板"""
        session = self.db_manager.get_session()
        try:
            template = ExamTemplate(
                name=name,
                description=description,
                category=category,
                total_score=total_score,
                paper_size=paper_size,
                is_system=False
            )
            template.set_structure(structure)

            session.add(template)
            session.commit()
            return template.id
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def update_template(self, template_id: int, **kwargs) -> bool:
        """更新模板"""
        session = self.db_manager.get_session()
        try:
            template = session.query(ExamTemplate).filter_by(id=template_id).first()
            if not template:
                return False

            # 系统模板不能修改
            if template.is_system:
                return False

            for key, value in kwargs.items():
                if key == 'structure':
                    template.set_structure(value)
                elif hasattr(template, key):
                    setattr(template, key, value)

            session.commit()
            return True
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def delete_template(self, template_id: int) -> bool:
        """删除模板"""
        session = self.db_manager.get_session()
        try:
            template = session.query(ExamTemplate).filter_by(id=template_id).first()
            if not template:
                return False

            # 系统模板不能删除
            if template.is_system:
                return False

            session.delete(template)
            session.commit()
            return True
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def generate_paper_from_template(self, template_id: int, paper_name: str,
                                    question_manager) -> int:
        """根据模板自动生成试卷"""
        session = self.db_manager.get_session()
        try:
            template = session.query(ExamTemplate).filter_by(id=template_id).first()
            if not template:
                raise Exception("模板不存在")

            structure = template.get_structure()

            # 创建试卷
            exam_paper = ExamPaper(
                name=paper_name,
                paper_size=template.paper_size,
                total_score=template.total_score,
                template_id=template_id,
                description=structure.get('header', {}).get('instructions', '')
            )
            session.add(exam_paper)
            session.flush()  # 获取试卷ID

            # 根据模板结构选题
            order_index = 0
            for section in structure.get('sections', []):
                section_type = section['type']
                count = section['count']
                score_per_item = section['score_per_item']
                difficulty_dist = section.get('difficulty', {})

                # 按难度分配题目数量
                for difficulty, num in difficulty_dist.items():
                    # 从题库中选择题目
                    questions = question_manager.search_questions(
                        question_type=section_type,
                        difficulty=difficulty,
                        limit=num
                    )

                    # 添加到试卷
                    from backend.database.models import ExamPaperQuestion
                    for q in questions:
                        epq = ExamPaperQuestion(
                            exam_paper_id=exam_paper.id,
                            question_id=q['id'],
                            order_index=order_index,
                            score=score_per_item
                        )
                        session.add(epq)
                        order_index += 1

            session.commit()
            return exam_paper.id

        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def get_template_statistics(self, template_id: int) -> Dict:
        """获取模板统计信息"""
        template = self.get_template(template_id)
        if not template:
            return {}

        structure = template['structure']
        sections = structure.get('sections', [])

        stats = {
            'total_questions': 0,
            'total_score': 0,
            'sections_count': len(sections),
            'question_types': {},
            'difficulty_distribution': {
                '简单': 0,
                '中等': 0,
                '困难': 0
            }
        }

        for section in sections:
            stats['total_questions'] += section['count']
            stats['total_score'] += section['total_score']

            q_type = section['type']
            if q_type not in stats['question_types']:
                stats['question_types'][q_type] = {
                    'count': 0,
                    'total_score': 0
                }

            stats['question_types'][q_type]['count'] += section['count']
            stats['question_types'][q_type]['total_score'] += section['total_score']

            # 统计难度分布
            for diff, count in section.get('difficulty', {}).items():
                if diff in stats['difficulty_distribution']:
                    stats['difficulty_distribution'][diff] += count

        return stats
