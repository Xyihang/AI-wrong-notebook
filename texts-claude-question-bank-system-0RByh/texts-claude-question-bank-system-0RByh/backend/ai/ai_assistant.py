"""
AI辅助识别和纠正模块
支持Claude和Gemini API
"""
import os
from typing import Dict, Any, List, Optional
from backend.ai.ai_providers import AIProvider, ClaudeProvider, GeminiProvider


class AIAssistant:
    """AI助手，用于OCR纠正和题目解析，支持多个AI提供商"""

    def __init__(self, provider: str = None):
        """
        初始化AI助手
        :param provider: AI提供商 'claude', 'gemini' 或 'auto'（自动选择）
        """
        self.provider_name = provider or os.getenv('AI_PROVIDER', 'auto')
        self.provider: Optional[AIProvider] = None
        self._init_provider()

    def _init_provider(self):
        """初始化AI提供商"""
        if self.provider_name == 'auto':
            # 自动选择：优先Claude，然后Gemini
            claude = ClaudeProvider()
            if claude.is_available():
                self.provider = claude
                self.provider_name = 'claude'
                print("✅ AI助手: 使用Claude")
                return

            gemini = GeminiProvider()
            if gemini.is_available():
                self.provider = gemini
                self.provider_name = 'gemini'
                print("✅ AI助手: 使用Gemini")
                return

            print("⚠️ AI助手: 无可用的AI提供商")

        elif self.provider_name.lower() == 'claude':
            claude = ClaudeProvider()
            if claude.is_available():
                self.provider = claude
                print("✅ AI助手: 使用Claude")
            else:
                print("❌ Claude不可用，请设置ANTHROPIC_API_KEY")

        elif self.provider_name.lower() == 'gemini':
            gemini = GeminiProvider()
            if gemini.is_available():
                self.provider = gemini
                print("✅ AI助手: 使用Gemini")
            else:
                print("❌ Gemini不可用，请设置GOOGLE_API_KEY或GEMINI_API_KEY")

        else:
            print(f"❌ 未知的AI提供商: {self.provider_name}")

    def is_available(self) -> bool:
        """检查AI助手是否可用"""
        return self.provider is not None and self.provider.is_available()

    def get_provider_info(self) -> Dict[str, Any]:
        """获取当前提供商信息"""
        if self.is_available():
            return {
                'available': True,
                'provider': self.provider.get_provider_name(),
                'provider_code': self.provider_name
            }
        return {
            'available': False,
            'provider': None,
            'provider_code': self.provider_name
        }

    def correct_ocr_text(self, ocr_text: str, confidence: float = 0.0) -> Dict[str, Any]:
        """
        使用AI纠正OCR识别的文本
        :param ocr_text: OCR识别的原始文本
        :param confidence: OCR识别的平均置信度
        :return: 纠正结果
        """
        if not self.is_available():
            return {
                'success': False,
                'error': 'AI助手不可用',
                'corrected_text': ocr_text,
                'original_text': ocr_text
            }

        return self.provider.correct_ocr_text(ocr_text, confidence)

    def parse_questions(self, text: str) -> Dict[str, Any]:
        """
        使用AI智能解析和提取题目
        :param text: 文本内容
        :return: 解析结果
        """
        if not self.is_available():
            return {
                'success': False,
                'error': 'AI助手不可用',
                'questions': []
            }

        return self.provider.parse_questions(text)

    def analyze_question(self, question_text: str) -> Dict[str, Any]:
        """
        分析单个题目，提取详细信息
        :param question_text: 题目文本
        :return: 分析结果
        """
        if not self.is_available():
            return {
                'success': False,
                'error': 'AI助手不可用'
            }

        return self.provider.analyze_question(question_text)

    def batch_correct_questions(self, questions: List[str]) -> Dict[str, Any]:
        """
        批量纠正和分析题目
        :param questions: 题目列表
        :return: 纠正和分析结果
        """
        if not self.is_available():
            return {
                'success': False,
                'error': 'AI助手不可用',
                'questions': questions
            }

        results = []
        for idx, question in enumerate(questions):
            try:
                analysis = self.analyze_question(question)
                if analysis['success']:
                    results.append({
                        'original': question,
                        'analysis': analysis,
                        'index': idx
                    })
                else:
                    results.append({
                        'original': question,
                        'error': analysis.get('error'),
                        'index': idx
                    })
            except Exception as e:
                results.append({
                    'original': question,
                    'error': str(e),
                    'index': idx
                })

        return {
            'success': True,
            'questions': results,
            'total': len(results),
            'provider': self.provider.get_provider_name() if self.provider else None
        }
