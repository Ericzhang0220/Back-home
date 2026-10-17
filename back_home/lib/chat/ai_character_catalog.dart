/// Authored character metadata, also used for older accounts whose documents
/// predate discovery tags. Gender is never inferred from an uploaded image.
const aiPresetMetadata = <String, ({String gender, List<String> tags})>{
  'ethan-miller': (
    gender: 'male',
    tags: ['basketball', 'camera', 'outgoing', 'competitive'],
  ),
  'noah-carter': (
    gender: 'male',
    tags: ['skateboard', 'music', 'palette', 'independent'],
  ),
  'liam-anderson': (gender: 'male', tags: ['code', 'soccer', 'thoughtful']),
  'mason-williams': (gender: 'male', tags: ['camping', 'calm', 'caring']),
  'caleb-johnson': (gender: 'male', tags: ['basketball', 'guitar', 'outgoing']),
  'ryan-thompson': (gender: 'male', tags: ['swimming', 'book', 'thoughtful']),
  'tyler-brown': (
    gender: 'male',
    tags: ['baseball', 'outgoing', 'adventurous'],
  ),
  'alex-davis': (gender: 'male', tags: ['camera', 'music', 'creative', 'calm']),
  'jake-wilson': (gender: 'male', tags: ['tennis', 'caring', 'calm']),
  'daniel-martinez': (
    gender: 'male',
    tags: ['soccer', 'palette', 'independent', 'creative'],
  ),
  'emma-wilson': (gender: 'female', tags: ['volleyball', 'music', 'outgoing']),
  'olivia-parker': (
    gender: 'female',
    tags: ['book', 'palette', 'calm', 'thoughtful'],
  ),
  'sophia-martinez': (gender: 'female', tags: ['dance', 'outgoing']),
  'ava-thompson': (
    gender: 'female',
    tags: ['camera', 'creative', 'independent'],
  ),
  'mia-anderson': (gender: 'female', tags: ['tennis', 'plants', 'caring']),
  'chloe-johnson': (
    gender: 'female',
    tags: ['basketball', 'music', 'competitive'],
  ),
  'isabella-brown': (
    gender: 'female',
    tags: ['palette', 'music', 'creative', 'calm'],
  ),
  'grace-miller': (
    gender: 'female',
    tags: ['book', 'swimming', 'caring', 'thoughtful'],
  ),
  'lily-davis': (gender: 'female', tags: ['hiking', 'adventurous', 'outgoing']),
  'hannah-carter': (
    gender: 'female',
    tags: ['guitar', 'code', 'independent', 'creative'],
  ),
  'theo-bennett': (gender: 'male', tags: ["witty", "tabletop", "calm"]),
  'kai-nakamura': (gender: 'male', tags: ["playful", "creative", "food"]),
  'rowan-brooks': (gender: 'male', tags: ["candid", "pragmatic", "plants"]),
  'jude-santos': (gender: 'male', tags: ["candid", "calm", "hiking"]),
  'felix-reed': (gender: 'male', tags: ["tabletop", "playful", "creative"]),
  'arlo-chen': (gender: 'male', tags: ["romantic", "journaling", "reflective"]),
  'dante-rivera': (
    gender: 'male',
    tags: ["candid", "empathetic", "independent"],
  ),
  'micah-okafor': (gender: 'male', tags: ["empathetic", "caring", "music"]),
  'ezra-singh': (
    gender: 'male',
    tags: ["reflective", "thoughtful", "tabletop"],
  ),
  'leo-moreau': (gender: 'male', tags: ["thrifting", "creative", "playful"]),
  'nico-park': (gender: 'male', tags: ["crafts", "reflective", "low-pressure"]),
  'owen-ellis': (gender: 'male', tags: ["cozy-games", "low-pressure", "calm"]),
  'hugo-alvarez': (gender: 'male', tags: ["offbeat", "creative", "tabletop"]),
  'samir-haddad': (gender: 'male', tags: ["empathetic", "thoughtful", "food"]),
  'soren-lind': (
    gender: 'male',
    tags: ["pragmatic", "low-pressure", "independent"],
  ),
  'iris-laurent': (gender: 'female', tags: ["offbeat", "witty", "plants"]),
  'sienna-patel': (
    gender: 'female',
    tags: ["empathetic", "thrifting", "playful"],
  ),
  'zoe-kim': (gender: 'female', tags: ["playful", "offbeat", "food"]),
  'freya-morgan': (
    gender: 'female',
    tags: ["candid", "pragmatic", "independent"],
  ),
  'maya-okafor': (gender: 'female', tags: ["caring", "pragmatic", "plants"]),
  'elena-rossi': (
    gender: 'female',
    tags: ["low-pressure", "empathetic", "calm"],
  ),
  'nora-chen': (
    gender: 'female',
    tags: ["journaling", "reflective", "empathetic"],
  ),
  'ruby-santos': (gender: 'female', tags: ["witty", "playful", "tabletop"]),
  'aisha-rahman': (
    gender: 'female',
    tags: ["astronomy", "thoughtful", "reflective"],
  ),
  'violet-hayes': (
    gender: 'female',
    tags: ["romantic", "camera", "reflective"],
  ),
  'lucia-vega': (gender: 'female', tags: ["food", "candid", "playful"]),
  'tessa-nguyen': (
    gender: 'female',
    tags: ["crafts", "playful", "low-pressure"],
  ),
  'cleo-brooks': (gender: 'female', tags: ["candid", "thoughtful", "tabletop"]),
  'june-park': (gender: 'female', tags: ["crafts", "low-pressure", "calm"]),
  'amara-diallo': (
    gender: 'female',
    tags: ["candid", "empathetic", "independent"],
  ),
};

const aiInterestLabels = <String, String>{
  'basketball': 'Basketball',
  'skateboard': 'Skating',
  'code': 'Coding',
  'camping': 'Camping',
  'swimming': 'Swimming',
  'baseball': 'Baseball',
  'music': 'Music',
  'tennis': 'Tennis',
  'soccer': 'Soccer',
  'volleyball': 'Volleyball',
  'book': 'Reading',
  'dance': 'Dance',
  'camera': 'Photography',
  'plants': 'Plants',
  'palette': 'Art',
  'hiking': 'Hiking',
  'guitar': 'Guitar',
  'caring': 'Caring',
  'calm': 'Calm',
  'outgoing': 'Outgoing',
  'creative': 'Creative',
  'adventurous': 'Adventurous',
  'thoughtful': 'Thoughtful',
  'competitive': 'Competitive',
  'independent': 'Independent',
  'witty': 'Witty',
  'playful': 'Playful',
  'candid': 'Candid',
  'empathetic': 'Empathetic',
  'romantic': 'Romantic',
  'pragmatic': 'Practical',
  'reflective': 'Reflective',
  'offbeat': 'Offbeat',
  'low-pressure': 'Low-pressure company',
  'tabletop': 'Tabletop games',
  'crafts': 'Crafts',
  'astronomy': 'Astronomy',
  'thrifting': 'Thrifting',
  'food': 'Food',
  'cozy-games': 'Cozy games',
  'journaling': 'Journaling',
};

/// Fallback for older or untagged custom characters, using only their authored
/// persona. English words are matched as words ("smart" must not imply "art").
List<String> aiTagsFromPersonality(String personality) {
  const keywords = <String, List<String>>{
    'caring': [
      'caring',
      'kind',
      'gentle',
      'supportive',
      'warm',
      '温柔',
      '体贴',
      '善良',
      '治愈',
    ],
    'calm': ['calm', 'patient', 'easygoing', '冷静', '沉稳', '耐心'],
    'outgoing': [
      'outgoing',
      'social',
      'talkative',
      'energetic',
      '外向',
      '开朗',
      '健谈',
      '活泼',
    ],
    'creative': ['creative', 'artistic', '创造', '艺术'],
    'adventurous': [
      'adventurous',
      'adventure',
      'travel',
      'traveling',
      '冒险',
      '旅行',
    ],
    'thoughtful': ['thoughtful', 'curious', 'observant', '思考', '好奇', '细心'],
    'competitive': ['competitive', 'competition', '竞争', '好胜'],
    'independent': ['independent', '独立'],
    'basketball': ['basketball', '篮球'],
    'skateboard': ['skating', 'skateboarding', 'skateboard', '滑板'],
    'code': ['coding', 'programming', 'coder', '编程', '代码'],
    'camping': ['camping', 'fishing', '露营', '钓鱼'],
    'swimming': ['swimming', '游泳'],
    'baseball': ['baseball', '棒球'],
    'music': ['music', 'piano', '音乐', '钢琴'],
    'tennis': ['tennis', '网球'],
    'soccer': ['soccer', 'football', '足球'],
    'volleyball': ['volleyball', '排球'],
    'book': ['reading', 'novels', 'books', '阅读', '读书', '小说'],
    'dance': ['dance', 'dancing', '跳舞', '舞蹈'],
    'camera': ['photography', 'photos', 'camera', '摄影', '拍照'],
    'plants': ['plants', 'gardening', '植物', '园艺'],
    'palette': ['painting', 'drawing', 'art', '画画', '绘画'],
    'hiking': ['hiking', '登山', '徒步'],
    'guitar': ['guitar', '吉他'],
  };
  final text = personality.toLowerCase();
  final words = text.split(RegExp(r'[^a-z]+')).toSet();
  return keywords.entries
      .where(
        (entry) => entry.value.any(
          (keyword) => RegExp(r'^[a-z]+$').hasMatch(keyword)
              ? words.contains(keyword)
              : text.contains(keyword),
        ),
      )
      .map((entry) => entry.key)
      .toList();
}
