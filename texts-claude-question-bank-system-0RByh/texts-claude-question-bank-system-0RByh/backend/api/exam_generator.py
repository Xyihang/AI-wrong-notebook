"""
组卷生成器
"""
from typing import List, Dict, Any, Optional
from ..database import DatabaseManager, Question, Tag, ExamPaper, ExamPaperQuestion
from sqlalchemy.orm import Session


class ExamGenerator:
    """试卷生成器"""

    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager

    def create_exam_paper(self, name: str, paper_size: str = 'A4',
                         total_score: float = 100.0,
                         description: Optional[str] = None) -> int:
        """
        创建试卷
        :param name: 试卷名称
        :param paper_size: 试卷尺寸（A4/A3）
        :param total_score: 总分
        :param description: 试卷说明
        :return: 试卷ID
        """
        session = self.db.get_session()
        try:
            exam_paper = ExamPaper(
                name=name,
                paper_size=paper_size,
                total_score=total_score,
                description=description
            )
            session.add(exam_paper)
            session.commit()
            paper_id = exam_paper.id
            return paper_id
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def add_question_to_paper(self, paper_id: int, question_id: int,
                             order_index: int, score: float = 0.0) -> bool:
        """
        向试卷添加题目
        :param paper_id: 试卷ID
        :param question_id: 题目ID
        :param order_index: 题目顺序
        :param score: 该题分数
        :return: 是否成功
        """
        session = self.db.get_session()
        try:
            paper_question = ExamPaperQuestion(
                exam_paper_id=paper_id,
                question_id=question_id,
                order_index=order_index,
                score=score
            )
            session.add(paper_question)
            session.commit()
            return True
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def generate_paper_by_selection(self, name: str, question_ids: List[int],
                                    scores: Optional[List[float]] = None,
                                    paper_size: str = 'A4',
                                    description: Optional[str] = None) -> int:
        """
        根据选定的题目生成试卷
        :param name: 试卷名称
        :param question_ids: 题目ID列表
        :param scores: 各题分数列表
        :param paper_size: 试卷尺寸
        :param description: 试卷说明
        :return: 试卷ID
        """
        # 创建试卷
        total_score = sum(scores) if scores else 100.0
        paper_id = self.create_exam_paper(name, paper_size, total_score, description)

        # 添加题目
        if not scores:
            # 如果没有指定分数，平均分配
            scores = [total_score / len(question_ids)] * len(question_ids)

        for idx, (question_id, score) in enumerate(zip(question_ids, scores)):
            self.add_question_to_paper(paper_id, question_id, idx + 1, score)

        return paper_id

    def generate_paper_by_criteria(self, name: str,
                                   tag_names: Optional[List[str]] = None,
                                   question_type: Optional[str] = None,
                                   difficulty: Optional[str] = None,
                                   count: int = 10,
                                   paper_size: str = 'A4',
                                   total_score: float = 100.0) -> int:
        """
        根据条件自动组卷
        :param name: 试卷名称
        :param tag_names: 知识点标签列表
        :param question_type: 题型
        :param difficulty: 难度
        :param count: 题目数量
        :param paper_size: 试卷尺寸
        :param total_score: 总分
        :return: 试卷ID
        """
        session = self.db.get_session()
        try:
            # 查询符合条件的题目
            query = session.query(Question)

            if tag_names:
                for tag_name in tag_names:
                    query = query.filter(Question.tags.any(Tag.name == tag_name))

            if question_type:
                query = query.filter(Question.question_type == question_type)

            if difficulty:
                query = query.filter(Question.difficulty == difficulty)

            questions = query.limit(count).all()

            if not questions:
                raise ValueError("没有找到符合条件的题目")

            # 创建试卷
            paper_id = self.create_exam_paper(name, paper_size, total_score)

            # 平均分配分数
            score_per_question = total_score / len(questions)

            # 添加题目到试卷
            for idx, question in enumerate(questions):
                self.add_question_to_paper(paper_id, question.id, idx + 1, score_per_question)

            return paper_id

        finally:
            session.close()

    def get_exam_paper(self, paper_id: int) -> Optional[Dict[str, Any]]:
        """
        获取试卷详情
        :param paper_id: 试卷ID
        :return: 试卷信息
        """
        session = self.db.get_session()
        try:
            paper = session.query(ExamPaper).get(paper_id)
            if not paper:
                return None

            # 获取试卷中的题目
            questions_data = []
            for pq in sorted(paper.paper_questions, key=lambda x: x.order_index):
                question = pq.question
                questions_data.append({
                    'order': pq.order_index,
                    'score': pq.score,
                    'id': question.id,
                    'content': question.content,
                    'question_type': question.question_type,
                    'difficulty': question.difficulty,
                    'answer': question.answer,
                    'analysis': question.analysis,
                    'tags': [tag.name for tag in question.tags]
                })

            return {
                'id': paper.id,
                'name': paper.name,
                'paper_size': paper.paper_size,
                'total_score': paper.total_score,
                'description': paper.description,
                'questions': questions_data,
                'question_count': len(questions_data),
                'created_at': paper.created_at.isoformat() if paper.created_at else None
            }
        finally:
            session.close()

    def get_all_exam_papers(self) -> List[Dict[str, Any]]:
        """
        获取所有试卷列表
        :return: 试卷列表
        """
        session = self.db.get_session()
        try:
            papers = session.query(ExamPaper).all()
            return [{
                'id': p.id,
                'name': p.name,
                'paper_size': p.paper_size,
                'total_score': p.total_score,
                'question_count': len(p.paper_questions),
                'created_at': p.created_at.isoformat() if p.created_at else None
            } for p in papers]
        finally:
            session.close()

    def delete_exam_paper(self, paper_id: int) -> bool:
        """
        删除试卷
        :param paper_id: 试卷ID
        :return: 是否成功
        """
        session = self.db.get_session()
        try:
            paper = session.query(ExamPaper).get(paper_id)
            if paper:
                session.delete(paper)
                session.commit()
                return True
            return False
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()
