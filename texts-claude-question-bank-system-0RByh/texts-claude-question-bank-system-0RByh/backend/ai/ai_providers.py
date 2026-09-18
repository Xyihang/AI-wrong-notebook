"""
AI提供商基类和具体实现
支持Claude和Gemini API
"""
import os
from typing import Dict, Any, List, Optional
from abc import ABC, abstractmethod


class AIProvider(ABC):
    """AI提供商基类"""

    @abstractmethod
    def is_available(self) -> bool:
        """检查提供商是否可用"""
        pass

    @abstractmethod
    def correct_ocr_text(self, ocr_text: str, confidence: float = 0.0) -> Dict[str, Any]:
        """纠正OCR文本"""
        pass

    @abstractmethod
    def parse_questions(self, text: str) -> Dict[str, Any]:
        """解析题目"""
        pass

    @abstractmethod
    def analyze_question(self, question_text: str) -> Dict[str, Any]:
        """分析单个题目"""
        pass

    @abstractmethod
    def get_provider_name(self) -> str:
        """获取提供商名称"""
        pass


class ClaudeProvider(AIProvider):
    """Claude AI提供商"""

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.getenv('ANTHROPIC_API_KEY')
        self.client = None

        if self.api_key:
            try:
                import anthropic
                self.client = anthropic.Anthropic(api_key=self.api_key)
            except Exception as e:
                print(f"初始化Claude客户端失败: {e}")
                self.client = None

    def is_available(self) -> bool:
        return self.client is not None

    def get_provider_name(self) -> str:
        return "Claude"

    def correct_ocr_text(self, ocr_text: str, confidence: float = 0.0) -> Dict[str, Any]:
        if not self.is_available():
            return {
                'success': False,
                'error': 'Claude不可用',
                'corrected_text': ocr_text
            }

        try:
            prompt = f"""Please correct the following text that was extracted using OCR. The text is primarily English with some Chinese descriptions. The OCR confidence is {confidence:.2%}.

Common OCR errors to watch for:
- Confusing similar characters (0/O, 1/l/I, 5/S, etc.)
- Missing or extra spaces
- Mathematical symbols and equations
- Special characters

Original OCR text:
---
{ocr_text}
---

Please provide:
1. The corrected text (fix obvious OCR errors but preserve the original structure)
2. A brief list of corrections made
3. Your confidence level (high/medium/low) in the corrections

Format your response as:
CORRECTED TEXT:
[corrected text here]

CORRECTIONS MADE:
- [list of corrections]

CONFIDENCE: [high/medium/low]"""

            message = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=4000,
                messages=[{"role": "user", "content": prompt}]
            )

            response_text = message.content[0].text

            # 解析响应
            corrected_text = ocr_text
            corrections = []
            ai_confidence = 'medium'

            if 'CORRECTED TEXT:' in response_text:
                parts = response_text.split('CORRECTED TEXT:')[1]
                if 'CORRECTIONS MADE:' in parts:
                    corrected_text = parts.split('CORRECTIONS MADE:')[0].strip()
                    corrections_part = parts.split('CORRECTIONS MADE:')[1]
                    if 'CONFIDENCE:' in corrections_part:
                        corrections_text = corrections_part.split('CONFIDENCE:')[0].strip()
                        ai_confidence = corrections_part.split('CONFIDENCE:')[1].strip().lower()
                        corrections = [c.strip('- ').strip() for c in corrections_text.split('\n') if c.strip()]
                else:
                    corrected_text = parts.strip()

            return {
                'success': True,
                'corrected_text': corrected_text,
                'original_text': ocr_text,
                'corrections': corrections,
                'ai_confidence': ai_confidence,
                'ocr_confidence': confidence,
                'provider': 'Claude'
            }

        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'corrected_text': ocr_text
            }

    def parse_questions(self, text: str) -> Dict[str, Any]:
        if not self.is_available():
            return {'success': False, 'error': 'Claude不可用', 'questions': []}

        try:
            prompt = f"""Please analyze the following text and extract individual questions. This text contains English exam questions (especially for Chinese middle school English exams) with some Chinese descriptions.

Text to analyze:
---
{text}
---

IMPORTANT: Identify and extract questions based on these common English exam question types:
1. **Multiple Choice (单选题)**: Four options A/B/C/D, choose the best answer
2. **Cloze Test (完形填空)**: Fill in blanks in a passage with provided options
3. **Reading Comprehension (阅读理解)**: Read a passage and answer multiple questions
4. **Task-based Reading (任务型阅读)**: Complete tables, answer questions based on passage
5. **Word Selection (选词填空)**: Choose words from a word bank to fill blanks
6. **Grammar Filling (语法填空)**: Fill blanks with correct grammar forms (may have hints)
7. **Spelling (单词拼写)**: Spell words based on context and hints
8. **Sentence Transformation (句型转换)**: Rewrite sentences keeping meaning
9. **Translation (翻译)**: Translate between Chinese and English
10. **Writing (书面表达)**: Essay writing based on prompts

Format your response as a JSON array with detailed information for each question.
If no clear questions are found, return an empty array []."""

            message = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=8000,
                messages=[{"role": "user", "content": prompt}]
            )

            response_text = message.content[0].text

            import json
            import re

            json_match = re.search(r'```json\s*([\s\S]*?)\s*```', response_text)
            if json_match:
                json_str = json_match.group(1)
                questions = json.loads(json_str)
            else:
                questions = json.loads(response_text)

            return {
                'success': True,
                'questions': questions,
                'total_questions': len(questions),
                'provider': 'Claude'
            }

        except Exception as e:
            return {'success': False, 'error': str(e), 'questions': []}

    def analyze_question(self, question_text: str) -> Dict[str, Any]:
        if not self.is_available():
            return {'success': False, 'error': 'Claude不可用'}

        try:
            prompt = f"""Analyze this question and provide detailed information in JSON format:

Question: {question_text}

Provide: question_type, difficulty, tags, subject, choices (if applicable), suggested_answer, notes."""

            message = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=2000,
                messages=[{"role": "user", "content": prompt}]
            )

            response_text = message.content[0].text

            import json
            import re

            json_match = re.search(r'```json\s*([\s\S]*?)\s*```', response_text)
            if json_match:
                analysis = json.loads(json_match.group(1))
            else:
                analysis = json.loads(response_text)

            return {'success': True, 'provider': 'Claude', **analysis}

        except Exception as e:
            return {'success': False, 'error': str(e)}


class GeminiProvider(AIProvider):
    """Google Gemini AI提供商"""

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.getenv('GOOGLE_API_KEY') or os.getenv('GEMINI_API_KEY')
        self.client = None

        if self.api_key:
            try:
                import google.generativeai as genai
                genai.configure(api_key=self.api_key)
                self.client = genai.GenerativeModel('gemini-1.5-pro')
            except Exception as e:
                print(f"初始化Gemini客户端失败: {e}")
                self.client = None

    def is_available(self) -> bool:
        return self.client is not None

    def get_provider_name(self) -> str:
        return "Gemini"

    def correct_ocr_text(self, ocr_text: str, confidence: float = 0.0) -> Dict[str, Any]:
        if not self.is_available():
            return {
                'success': False,
                'error': 'Gemini不可用',
                'corrected_text': ocr_text
            }

        try:
            prompt = f"""Please correct the following OCR text. The text is primarily English with some Chinese descriptions. OCR confidence: {confidence:.2%}.

Common OCR errors to watch for:
- Similar characters (0/O, 1/l/I, 5/S)
- Missing/extra spaces
- Mathematical symbols

Original text:
---
{ocr_text}
---

Provide:
1. Corrected text
2. List of corrections made
3. Confidence level (high/medium/low)

Format:
CORRECTED TEXT:
[text]

CORRECTIONS MADE:
- [list]

CONFIDENCE: [level]"""

            response = self.client.generate_content(prompt)
            response_text = response.text

            # 解析响应（同Claude）
            corrected_text = ocr_text
            corrections = []
            ai_confidence = 'medium'

            if 'CORRECTED TEXT:' in response_text:
                parts = response_text.split('CORRECTED TEXT:')[1]
                if 'CORRECTIONS MADE:' in parts:
                    corrected_text = parts.split('CORRECTIONS MADE:')[0].strip()
                    corrections_part = parts.split('CORRECTIONS MADE:')[1]
                    if 'CONFIDENCE:' in corrections_part:
                        corrections_text = corrections_part.split('CONFIDENCE:')[0].strip()
                        ai_confidence = corrections_part.split('CONFIDENCE:')[1].strip().lower()
                        corrections = [c.strip('- ').strip() for c in corrections_text.split('\n') if c.strip()]

            return {
                'success': True,
                'corrected_text': corrected_text,
                'original_text': ocr_text,
                'corrections': corrections,
                'ai_confidence': ai_confidence,
                'ocr_confidence': confidence,
                'provider': 'Gemini'
            }

        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'corrected_text': ocr_text
            }

    def parse_questions(self, text: str) -> Dict[str, Any]:
        if not self.is_available():
            return {'success': False, 'error': 'Gemini不可用', 'questions': []}

        try:
            prompt = f"""Analyze this text and extract exam questions (Chinese middle school English exam format).

Text:
---
{text}
---

Identify these question types:
1. Multiple Choice (单选题)
2. Cloze Test (完形填空)
3. Reading Comprehension (阅读理解)
4. Task-based Reading (任务型阅读)
5. Word Selection (选词填空)
6. Grammar Filling (语法填空)
7. Spelling (单词拼写)
8. Sentence Transformation (句型转换)
9. Translation (翻译)
10. Writing (书面表达)

Return JSON array with: question_number, content, question_type, sub_type, difficulty, choices, passage, tags, notes.
Return [] if no questions found."""

            response = self.client.generate_content(prompt)
            response_text = response.text

            import json
            import re

            # 尝试提取JSON
            json_match = re.search(r'```json\s*([\s\S]*?)\s*```', response_text)
            if json_match:
                questions = json.loads(json_match.group(1))
            else:
                # 尝试找到数组
                array_match = re.search(r'\[[\s\S]*\]', response_text)
                if array_match:
                    questions = json.loads(array_match.group(0))
                else:
                    questions = []

            return {
                'success': True,
                'questions': questions,
                'total_questions': len(questions),
                'provider': 'Gemini'
            }

        except Exception as e:
            return {'success': False, 'error': str(e), 'questions': []}

    def analyze_question(self, question_text: str) -> Dict[str, Any]:
        if not self.is_available():
            return {'success': False, 'error': 'Gemini不可用'}

        try:
            prompt = f"""Analyze this question in JSON format:

Question: {question_text}

Provide: question_type, difficulty, difficulty_reasoning, tags, subject, choices, suggested_answer, notes."""

            response = self.client.generate_content(prompt)
            response_text = response.text

            import json
            import re

            json_match = re.search(r'```json\s*([\s\S]*?)\s*```', response_text)
            if json_match:
                analysis = json.loads(json_match.group(1))
            else:
                obj_match = re.search(r'\{[\s\S]*\}', response_text)
                if obj_match:
                    analysis = json.loads(obj_match.group(0))
                else:
                    analysis = {}

            return {'success': True, 'provider': 'Gemini', **analysis}

        except Exception as e:
            return {'success': False, 'error': str(e)}
