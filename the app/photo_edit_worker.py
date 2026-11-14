"""Offline inference worker for  background/object edits. No file outputs."""
import base64
import io
import json
import os
import sys

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['TOKENIZERS_PARALLELISM'] = 'false'

ARABIC_EN_MAP = {
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
    words = text.split()
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
        elif any('\u0600' <= c <= '\u06ff' for c in word):
            has_arabic = True
        else:
            translated.append(word)
    if has_arabic and translated:
        return ' '.join(translated)
    return text


def main():
    from PIL import Image
    import torch
    import cv2
    from diffusers import StableDiffusionInpaintPipeline, DPMSolverMultistepScheduler
    import numpy as np
    from photo_edit import BASE_MODEL, REMOVAL_MODEL, PREFIX, WORK_SIZE, validate_options, png64

    raw = sys.stdin.buffer.read(10*1024*1024+1)
    if len(raw) > 10*1024*1024:
        raise ValueError('The edit request is too large')
    request = json.loads(raw)
    options = validate_options({k:request[k] for k in ('operation','instruction','steps','seed','strength') if k in request})
    def image(key, mode):
        opened = Image.open(io.BytesIO(base64.b64decode(request[key],validate=True)))
        if opened.size != (WORK_SIZE,WORK_SIZE):
            raise ValueError('Unsupported edit dimensions')
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

    pipe = StableDiffusionInpaintPipeline.from_pretrained(str(BASE_MODEL),local_files_only=True,
        use_safetensors=True,torch_dtype=dtype,safety_checker=None,requires_safety_checker=False)
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

    pipe.enable_attention_slicing()
    pipe.enable_vae_slicing()
    pipe.to(device)
    pipe.set_progress_bar_config(disable=True)

    translated_instruction = translate_instruction(options['instruction'])
    prompt = (
        f"RAW photograph of (({translated_instruction}):1.25), tailored fit, "
        "natural clothing folds, fabric texture, realistic human proportions, "
        "hyperrealistic, 8k uhd, dslr, soft studio lighting"
    )
    # Ensure prompt stays within CLIP token limit (77 tokens) without failing the job
    if len(pipe.tokenizer(prompt, truncation=False).input_ids) > pipe.tokenizer.model_max_length:
        input_ids = pipe.tokenizer(
            prompt,
            truncation=True,
            max_length=pipe.tokenizer.model_max_length - 2,
        ).input_ids
        prompt = pipe.tokenizer.decode(input_ids, skip_special_tokens=True)

    negative = (
        "(deformed, distorted, disfigured:1.35), (bad anatomy, wrong anatomy:1.2), "
        "extra limb, missing limb, floating limbs, (mutated hands and fingers:1.4), "
        "disconnected limbs, mutation, mutated, ugly, blurry, amputation, "
        "unnatural body proportions, warped fabric, disproportional body, bloated, "
        "artifacts, lowres, low quality, duplicate, text, watermark"
    )

    strength = float(options.get('strength', 0.85))
    strength = max(0.2, min(1.0, strength))

    generated = pipe(prompt=prompt, negative_prompt=negative, image=original, mask_image=mask,
                     height=WORK_SIZE, width=WORK_SIZE, strength=strength,
                     num_inference_steps=options['steps'], guidance_scale=7.5,
                     generator=torch.Generator(device=device).manual_seed(options['seed']))

    print(PREFIX+json.dumps(dict(safe=True,image=png64(np.asarray(generated.images[0].convert('RGB'))))),flush=True)


if __name__ == '__main__':
    main()
