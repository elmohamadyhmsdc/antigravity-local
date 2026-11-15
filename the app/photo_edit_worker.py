"""Offline inference worker for masked photo edits. No file outputs."""
import base64
import io
import json
import os
import re
import sys

ARABIC_EN_MAP = {
    'مايوه': 'swimwear', 'مايوهات': 'swimwear', 'سباحه': 'swimming',
    'البحر': 'the sea', 'بحر': 'sea', 'الشاطئ': 'the beach', 'شاطئ': 'beach',
    'بدون': 'without', 'منغير': 'without', 'صدر': 'chest', 'بطن': 'abdomen',
    'ذراع': 'arm', 'ذراعين': 'arms', 'ساق': 'leg', 'ساقين': 'legs', 'جسم': 'body',
    'بشره': 'skin', 'مكشوف': 'bare', 'عاري': 'bare', 'شيل': 'remove', 'اشيل': 'remove',
    # Clothing / garments
    'بدله': 'formal business suit', 'طقم': 'outfit suit',
    'بليزر': 'blazer jacket', 'توكسيدو': 'tuxedo suit', 'فيست': 'vest', 'صديري': 'waistcoat vest',
    'فستان': 'elegant dress', 'فساتين': 'dresses', 'دريس': 'dress',
    'جيبه': 'skirt', 'تنوره': 'skirt', 'بلوزه': 'blouse',
    'قميص': 'shirt', 'قمصان': 'shirts',
    'تيشيرت': 't-shirt', 'تيشرت': 't-shirt', 'تشرت': 't-shirt', 'بولو': 'polo shirt',
    'بنطلون': 'trousers pants', 'بنطال': 'trousers pants', 'بناطيل': 'trousers',
    'جينز': 'denim jeans', 'شورت': 'shorts',
    'جاكيت': 'jacket', 'جاكت': 'jacket', 'معطف': 'coat', 'بالطو': 'overcoat',
    'بلوفر': 'sweater pullover', 'سويتر': 'sweater',
    'سويت شيرت': 'hoodie sweatshirt', 'سويتشرت': 'hoodie sweatshirt', 'هودي': 'hoodie',
    'عبايه': 'abaya', 'عباءه': 'abaya', 'حجاب': 'hijab scarf', 'طرحه': 'scarf',
    'كاب': 'baseball cap', 'طاقيه': 'hat', 'قبعه': 'hat', 'برنيطه': 'fedora hat',
    'حذاء': 'shoes', 'احذيه': 'shoes', 'كوتشي': 'sneakers', 'جزمه': 'boots', 'صندل': 'sandals',
    'ساعه': 'luxury wristwatch',
    'نظاره': 'glasses', 'نضاره': 'sunglasses', 'نظارات': 'glasses', 'نضارات': 'sunglasses',
    'شنطه': 'leather handbag', 'حقيبه': 'handbag',
    'كرفته': 'necktie', 'كرافته': 'necktie', 'ربطه عنق': 'necktie', 'بيبيون': 'bowtie',
    'حزام': 'leather belt', 'سلسله': 'necklace', 'عقد': 'necklace', 'خاتم': 'ring', 'اسوره': 'bracelet',
    # Colors
    'احمر': 'red', 'حمراء': 'red', 'نبيتي': 'burgundy maroon',
    'ازرق': 'blue', 'زرقاء': 'blue',
    'كحلي': 'navy blue', 'سماوي': 'sky blue',
    'اسود': 'black', 'سوداء': 'black',
    'ابيض': 'white', 'بيضاء': 'white',
    'اخضر': 'green', 'خضراء': 'green', 'زيتي': 'olive green',
    'اصفر': 'yellow', 'صفراء': 'yellow',
    'رمادي': 'grey', 'رصاصي': 'charcoal grey',
    'بني': 'brown', 'بيج': 'beige', 'بيتش': 'peach',
    'وردي': 'pink', 'بمبي': 'pink', 'روز': 'rose pink',
    'بنفسجي': 'purple', 'موف': 'violet purple',
    'ذهبي': 'golden', 'فضي': 'silver', 'برونزي': 'bronze',
    # Materials
    'جلد': 'leather', 'حرير': 'silk', 'صوف': 'wool', 'قطن': 'cotton',
    'كتان': 'linen', 'مخمل': 'velvet', 'شيفون': 'chiffon', 'ستان': 'satin',
    'ساتان': 'satin', 'دانتيل': 'lace',
    # Styles
    'سواريه': 'evening party', 'كلاسيك': 'formal classic', 'فورمال': 'formal',
    'كاجوال': 'casual', 'انيق': 'elegant', 'شيك': 'stylish chic',
    'فخم': 'luxurious', 'ضيق': 'slim fit', 'واسع': 'oversized relaxed fit',
    'كاروهات': 'plaid checkered', 'مقلم': 'striped', 'ساده': 'solid plain',
    'صيفي': 'summer', 'شتوي': 'winter', 'رياضي': 'sportswear athletic',
}


def normalize_arabic(text: str) -> str:
    text = text.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
    text = text.replace('ة', 'ه').replace('ى', 'ي')
    return text


def translate_instruction(text: str) -> str:
    words = re.sub(r'\bمن\s+غير\b', 'منغير', text).split()
    translated = []
    has_arabic = False
    for word in words:
        clean = word.strip('.,!?-،؛:"\'')
        norm = normalize_arabic(clean.lower())
        if norm in ARABIC_EN_MAP:
            translated.append(ARABIC_EN_MAP[norm])
            has_arabic = True
        elif norm.startswith('ال') and len(norm) > 3 and norm[2:] in ARABIC_EN_MAP:
            translated.append(ARABIC_EN_MAP[norm[2:]])
            has_arabic = True
        elif norm.startswith('و') and norm[1:].removeprefix('ال') in ARABIC_EN_MAP:
            translated.append('and ' + ARABIC_EN_MAP[norm[1:].removeprefix('ال')])
            has_arabic = True
        elif any('\u0600' <= c <= '\u06ff' for c in word):
            has_arabic = True
        else:
            translated.append(word)
    if has_arabic and translated:
        return ' '.join(translated)
    return text


def main():
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['TRANSFORMERS_OFFLINE'] = '1'
    os.environ['TOKENIZERS_PARALLELISM'] = 'false'

    from PIL import Image
    import torch
    import cv2
    from diffusers import StableDiffusionInpaintPipeline, DPMSolverMultistepScheduler
    import numpy as np
    from photo_edit import (
        APP, BASE_MODEL, CYBER_MODEL, SDXL_MODEL, REMOVAL_MODEL, PREFIX,
        WORK_SIZE, WORK_SIZE_SDXL, MODEL_SDXL, MODEL_CYBER_REALISTIC, MODEL_REALISTIC_VISION,
        validate_options, png64
    )

    raw = sys.stdin.buffer.read(10*1024*1024+1)
    if len(raw) > 10*1024*1024:
        raise ValueError('The edit request is too large')
    request = json.loads(raw)
    if request.get('task') == 'parse_clothes':
        from mobile_api.model_readiness import clothing_parser_path
        from transformers import AutoModelForSemanticSegmentation, SegformerImageProcessor
        from undress_engine import parse_clothes

        local = clothing_parser_path(APP)
        if local is None:
            raise ValueError('The local clothing parser is missing')
        torch.set_num_threads(min(4, os.cpu_count() or 1))
        processor = SegformerImageProcessor.from_pretrained(str(local), local_files_only=True)
        parser = AutoModelForSemanticSegmentation.from_pretrained(str(local), local_files_only=True).eval()
        with Image.open(io.BytesIO(base64.b64decode(request['image'], validate=True))) as image:
            labels = parse_clothes(image.convert('RGB'), processor, parser)
        print(PREFIX + json.dumps(dict(safe=True, image=png64(labels))), flush=True)
        return
    options = validate_options({k:request[k] for k in ('operation','instruction','steps','seed','strength','model') if k in request})
    model_choice = options.get('model', MODEL_REALISTIC_VISION)
    work_size = int(request.get('work_size', WORK_SIZE_SDXL if model_choice == MODEL_SDXL else WORK_SIZE))

    def image(key, mode):
        opened = Image.open(io.BytesIO(base64.b64decode(request[key],validate=True)))
        if opened.size != (work_size, work_size):
            raise ValueError(f'Unsupported edit dimensions: {opened.size} != {(work_size, work_size)}')
        return opened.convert(mode)
    original,mask = image('image','RGB'),image('mask','L')
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    dtype = torch.float16 if device == 'cuda' else torch.float32

    if options['operation'] == 'remove':
        # Big-LaMa deep inpainting with boundary dilation eliminates ghosting and fills naturally
        import hashlib
        from download_photo_edit_removal import SHA256
        with REMOVAL_MODEL.open('rb') as source:
            digest = hashlib.sha256(source.read()).hexdigest()
        if digest != SHA256:
            raise ValueError('Object-removal model checksum mismatch')
        model = torch.jit.load(str(REMOVAL_MODEL),map_location=device).eval()
        pixels = torch.from_numpy(np.asarray(original).copy().transpose(2,0,1)).float().div(255).unsqueeze(0).to(device)
        mask_np = np.asarray(mask)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        dilated = cv2.dilate(mask_np, kernel, iterations=1)
        selected = torch.from_numpy((dilated >= 128).astype(np.float32)).unsqueeze(0).unsqueeze(0).to(device)
        with torch.inference_mode():
            result = model(pixels,selected)[0].permute(1,2,0).float().cpu().numpy()
        result = np.clip(result,0,1)
        print(PREFIX+json.dumps(dict(safe=True,image=png64((result*255).clip(0,255).astype(np.uint8)))),flush=True)
        return

    references = request.get('references', [])
    if references:
        from mobile_api.reference_reface import load_reference_inpaint_pipeline

        pipe = load_reference_inpaint_pipeline(.65)
    elif model_choice == MODEL_SDXL:
        from diffusers import StableDiffusionXLInpaintPipeline
        pipe = StableDiffusionXLInpaintPipeline.from_pretrained(
            str(SDXL_MODEL),
            variant='fp16',
            local_files_only=True,
            torch_dtype=dtype,
            use_safetensors=True,
        )
    elif model_choice == MODEL_CYBER_REALISTIC:
        pipe = StableDiffusionInpaintPipeline.from_single_file(
            str(CYBER_MODEL),
            local_files_only=True,
            torch_dtype=dtype,
            safety_checker=None,
        )
    else:
        pipe = StableDiffusionInpaintPipeline.from_pretrained(
            str(BASE_MODEL),
            local_files_only=True,
            use_safetensors=True,
            torch_dtype=dtype,
            safety_checker=None,
            requires_safety_checker=False,
        )

    try:
        pipe.scheduler = DPMSolverMultistepScheduler.from_config(
            pipe.scheduler.config,
            use_karras_sigmas=True,
            algorithm_type="sde-dpmsolver++",
        )
    except Exception:
        try:
            pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, use_karras_sigmas=True)
        except Exception:
            pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config)

    if not references:
        if hasattr(pipe, 'enable_attention_slicing'):
            pipe.enable_attention_slicing()
        if hasattr(pipe, 'enable_vae_slicing'):
            pipe.enable_vae_slicing()
        pipe.to(device)
    pipe.set_progress_bar_config(disable=True)

    translated_instruction = translate_instruction(options['instruction'])
    prompt = (
        f"{translated_instruction}, photorealistic, natural texture and proportions, "
        "matching the perspective and lighting of the surrounding photo"
    )
    if request.get('preserve_body_shape'):
        prompt += ', original build and pose of the person, ordinary unretouched skin texture'
    # Ensure prompt stays within CLIP token limit (77 tokens) without failing the job
    tokenizer = getattr(pipe, 'tokenizer', None)
    if tokenizer is not None and hasattr(tokenizer, 'model_max_length'):
        if len(tokenizer(prompt, truncation=False).input_ids) > tokenizer.model_max_length:
            input_ids = tokenizer(
                prompt,
                truncation=True,
                max_length=tokenizer.model_max_length - 2,
            ).input_ids
            prompt = tokenizer.decode(input_ids, skip_special_tokens=True)

    negative = (
        "(deformed, distorted, disfigured:1.35), (bad anatomy, wrong anatomy:1.2), "
        "extra limb, missing limb, floating limbs, (mutated hands and fingers:1.4), "
        "disconnected limbs, mutation, mutated, ugly, blurry, amputation, "
        "unnatural body proportions, warped fabric, disproportional body, bloated, "
        "artifacts, lowres, low quality, duplicate, text, watermark"
    )
    if request.get('preserve_body_shape'):
        negative += ', exaggerated muscle definition, sculpted abs, fitness model, plastic skin, leftover cuffs, stray garment logos'

    strength = float(options.get('strength', 0.85))
    strength = max(0.2, min(1.0, strength))

    guidance = {}
    if references:
        images = []
        for encoded in references:
            with Image.open(io.BytesIO(base64.b64decode(encoded, validate=True))) as reference:
                images.append(reference.convert('RGB'))
        # One adapter with several images, rather than one adapter per reference.
        guidance['ip_adapter_image'] = [images]
    generated = pipe(prompt=prompt, negative_prompt=negative, image=original, mask_image=mask,
                     height=work_size, width=work_size, strength=strength,
                     num_inference_steps=options['steps'], guidance_scale=7.5,
                     generator=torch.Generator(device='cpu' if references else device).manual_seed(options['seed']),
                     **guidance)

    print(PREFIX+json.dumps(dict(safe=True,image=png64(np.asarray(generated.images[0].convert('RGB'))))),flush=True)


if __name__ == '__main__':
    main()
