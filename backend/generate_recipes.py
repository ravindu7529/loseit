import random
random.seed(42)

recipes = []  # each: dict

# ---------------------------------------------------------------
# Reference data
# ---------------------------------------------------------------

proteins = {
    "Chicken": ("Non-Vegetarian", ["Curry", "Black Curry (Kalu Pol)", "White Curry (Kiri Hodi)",
                                    "Devilled", "Kottu", "Fried Rice", "Biryani", "Roast", "Soup (Kool)"]),
    "Fish (Tuna)": ("Pescatarian", ["Curry", "Ambul Thiyal", "Devilled", "Cutlet", "Kottu", "Fried Rice"]),
    "Fish (Seer/Thora)": ("Pescatarian", ["Curry", "White Curry (Kiri Hodi)", "Ambul Thiyal", "Fried"]),
    "Prawns": ("Pescatarian", ["Curry", "Devilled", "Ambul Thiyal", "Wade", "Kottu", "Fried Rice", "Soup (Kool)"]),
    "Cuttlefish": ("Pescatarian", ["Curry", "Devilled", "Black Curry (Kalu Pol)"]),
    "Crab": ("Pescatarian", ["Curry", "Devilled", "Soup (Kool)"]),
    "Beef": ("Non-Vegetarian", ["Curry", "Black Curry (Kalu Pol)", "Devilled", "Kottu", "Fried Rice", "Roast", "Ambul Thiyal"]),
    "Pork": ("Non-Vegetarian", ["Curry", "Black Curry (Kalu Pol)", "Devilled", "Ambul Thiyal"]),
    "Mutton": ("Non-Vegetarian", ["Curry", "Black Curry (Kalu Pol)", "Kottu", "Biryani", "Devilled"]),
    "Egg": ("Vegetarian", ["Curry", "Kottu", "Fried Rice", "Roll", "Devilled"]),
    "Dried Sprats (Halmasso)": ("Pescatarian", ["Sambol", "Curry", "Devilled"]),
    "Dried Fish (Karawala)": ("Pescatarian", ["Sambol", "Curry", "Tempered (Thel Dala)"]),
}

veggies = {
    "Brinjal (Eggplant)": ["Curry", "Black Curry (Kalu Pol)", "Moju", "Tempered (Thel Dala)"],
    "Okra (Bandakka)": ["Curry", "Tempered (Thel Dala)", "White Curry (Kiri Hodi)"],
    "Pumpkin (Wattakka)": ["Curry", "White Curry (Kiri Hodi)", "Tempered (Thel Dala)"],
    "Young Jackfruit (Polos)": ["Curry", "Black Curry (Kalu Pol)"],
    "Jackfruit Seed (Kos Ata)": ["Curry", "Tempered (Thel Dala)"],
    "Breadfruit (Del)": ["Curry", "White Curry (Kiri Hodi)"],
    "Ash Plantain (Alu Kesel)": ["Curry", "White Curry (Kiri Hodi)", "Mallung"],
    "Manioc (Kappa)": ["Curry", "Tempered (Thel Dala)"],
    "Beetroot": ["Curry", "Tempered (Thel Dala)"],
    "Carrot": ["Curry", "Tempered (Thel Dala)"],
    "Green Beans (Bonchi)": ["Curry", "Tempered (Thel Dala)"],
    "Potato (Ala)": ["Curry", "Tempered (Thel Dala)", "White Curry (Kiri Hodi)"],
    "Drumstick (Murunga)": ["Curry", "White Curry (Kiri Hodi)"],
    "Snake Gourd (Pathola)": ["Curry", "Tempered (Thel Dala)"],
    "Bitter Gourd (Karawila)": ["Curry", "Tempered (Thel Dala)", "Devilled"],
    "Mushroom": ["Curry", "White Curry (Kiri Hodi)", "Devilled"],
    "Cashew Nut": ["Curry", "White Curry (Kiri Hodi)"],
    "Chickpea (Kadala)": ["Curry"],
    "Red Lentil (Parippu)": ["Curry", "Wade"],
    "Soya Meat": ["Curry", "Devilled", "Kottu"],
    "Tofu": ["Curry", "Devilled", "Kottu"],
    "Green Mango": ["Curry", "Achcharu (Pickle)"],
    "Pineapple": ["Curry", "Moju"],
    "Elumas (Jackfruit Seed & Skin)": ["Curry", "Tempered (Thel Dala)"],
    "Winged Bean (Dara Dambala)": ["Curry", "Tempered (Thel Dala)"],
}

leafy = {
    "Gotukola": ["Mallung", "Sambol"],
    "Kankun (Water Spinach)": ["Mallung", "Tempered (Thel Dala)"],
    "Mukunuwenna": ["Mallung"],
    "Spinach (Nivithi)": ["Mallung", "Curry"],
    "Cabbage": ["Mallung", "Curry", "Tempered (Thel Dala)"],
    "Sarana Leaves": ["Mallung"],
}

sambols = [
    "Pol Sambol (Coconut Sambol)", "Katta Sambol", "Seeni Sambol (Caramelised Onion)",
    "Lunu Miris", "Ash Plantain Sambol", "Carrot Sambol", "Dried Sprats Sambol",
    "Karawala Sambol", "Gotukola Sambol", "Green Chili Sambol", "Onion Sambol",
    "Tomato Sambol", "Green Mango Sambol", "Pineapple Sambol",
]

rice_grain = [
    "Kiribath (Milk Rice)", "Yellow Rice", "Ghee Rice", "Chicken Lamprais",
    "Vegetable Lamprais", "String Hopper Biryani", "Red Rice and Curry Plate",
]

bread_hoppers = [
    "Plain Hoppers", "Egg Hoppers", "Milk Hoppers", "String Hoppers",
    "Pittu (Rice Flour & Coconut)", "Kurakkan Pittu", "Godamba Roti",
    "Pol Roti (Coconut Roti)", "Roti with Katta Sambol",
]

short_eats = [
    "Fish Cutlets", "Fish Rolls", "Vegetable Rolls", "Egg Rolls",
    "Chicken Patties", "Fish Patties", "Vegetable Patties",
    "Ulundu Wade (Lentil Fritters)", "Parippu Wade", "Isso Wade (Prawn Fritters)",
    "Maalu Paan (Fish Bun)",
]

desserts = [
    "Kavum (Oil Cake)", "Kokis", "Athirasa", "Aluwa", "Aasmi",
    "Undu Walalu", "Bibikkan (Coconut Cake)", "Watalappan", "Rice Payasam",
    "Semiya Payasam", "Curd and Treacle", "Love Cake", "Wattakka Bibikkan",
    "Rulan Cake",
]

breakfast_porridge = [
    "Kola Kanda (Herbal Rice Porridge)", "Rice Kanda", "Kurakkan Roti", "Red Rice Congee",
]

beverages = [
    "King Coconut Water", "Faluda", "Belimal Tea", "Ranawara Herbal Tea", "Thambili Juice",
]

regions = ["Jaffna-style ", "Negombo-style ", "Kandyan-style ", "Southern-style ", ""]

# ---------------------------------------------------------------
# Nutrition profiles: (cal_lo, cal_hi, protein_lo, protein_hi, carb_lo, carb_hi, fat_lo, fat_hi, fiber_lo, fiber_hi)
# ---------------------------------------------------------------

profiles = {
    "Curry-Protein":        (220, 380, 18, 30, 5, 12, 12, 24, 1, 3),
    "Curry-Protein-Black":  (200, 340, 18, 28, 5, 12, 8, 18, 1, 3),
    "Curry-Protein-White":  (240, 400, 16, 26, 6, 13, 16, 28, 1, 3),
    "Devilled":             (260, 380, 18, 30, 8, 16, 12, 22, 1, 3),
    "Ambul Thiyal":         (200, 300, 24, 32, 2, 6, 6, 14, 0, 2),
    "Kottu":                (450, 650, 15, 30, 55, 75, 15, 25, 3, 6),
    "Fried Rice":           (380, 550, 10, 22, 55, 75, 10, 18, 2, 4),
    "Biryani":              (480, 650, 18, 28, 60, 80, 12, 22, 2, 4),
    "Roast":                (250, 360, 22, 32, 3, 8, 12, 20, 0, 2),
    "Soup (Kool)":          (140, 240, 12, 22, 8, 16, 3, 9, 1, 3),
    "Cutlet":               (150, 250, 8, 14, 12, 20, 8, 16, 1, 2),
    "Fried":                (220, 320, 20, 28, 4, 10, 10, 18, 0, 2),
    "Wade":                 (160, 260, 6, 12, 18, 28, 7, 14, 3, 5),
    "Roll":                 (170, 260, 6, 12, 16, 26, 8, 16, 1, 3),
    "Sambol":               (70, 150, 1, 3, 5, 10, 5, 10, 2, 4),
    "Curry-Veg":            (110, 220, 2, 5, 10, 22, 6, 14, 3, 6),
    "Black Curry (Kalu Pol)": (110, 210, 2, 5, 10, 20, 5, 12, 3, 6),
    "White Curry (Kiri Hodi)": (140, 250, 2, 5, 10, 20, 9, 18, 2, 5),
    "Tempered (Thel Dala)":(80, 160, 2, 4, 6, 14, 4, 9, 2, 5),
    "Moju":                 (90, 160, 1, 3, 10, 18, 4, 9, 2, 4),
    "Achcharu (Pickle)":    (60, 120, 1, 2, 8, 16, 2, 6, 1, 3),
    "Mallung":              (60, 110, 2, 4, 5, 10, 3, 6, 4, 7),
    "Rice/Grain":           (250, 420, 5, 12, 45, 70, 5, 14, 1, 3),
    "Bread/Hopper":         (90, 220, 3, 7, 15, 30, 3, 9, 1, 3),
    "Short Eats":           (150, 280, 5, 10, 15, 24, 8, 16, 1, 2),
    "Dessert":              (180, 330, 2, 6, 22, 42, 7, 16, 1, 3),
    "Breakfast Porridge":   (90, 160, 2, 5, 14, 26, 2, 6, 2, 4),
    "Beverage":             (40, 140, 0, 2, 8, 30, 0, 2, 0, 1),
}

descriptors = [
    "A traditional Sri Lankan favourite, slow-cooked with authentic island spices.",
    "A home-style dish popular across Sri Lankan households.",
    "A classic preparation balancing heat, tang and coconut richness.",
    "A comforting dish commonly served with rice and curry.",
    "A well-loved recipe passed down through generations.",
    "A fragrant dish built on roasted curry powder and fresh curry leaves.",
    "A light, everyday preparation valued for its simplicity and flavour.",
    "A festive dish often prepared for special occasions.",
]

# ---------------------------------------------------------------
# Ingredient templates
# ---------------------------------------------------------------

def key_ingredients(main, style):
    base = {
        "Curry-Protein": [main, "coconut milk", "curry leaves", "onion", "roasted curry powder"],
        "Curry-Protein-Black": [main, "roasted curry powder", "coconut milk", "garlic", "cinnamon"],
        "Curry-Protein-White": [main, "coconut milk", "pandan leaf", "green chili", "lemongrass"],
        "Devilled": [main, "capsicum", "onion", "soy sauce", "chili flakes"],
        "Ambul Thiyal": [main, "goraka (dried garcinia)", "black pepper", "curry leaves"],
        "Kottu": [main, "godamba roti", "carrot", "leeks", "egg"],
        "Fried Rice": [main, "rice", "carrot", "egg", "spring onion"],
        "Biryani": [main, "basmati rice", "cashew", "raisins", "biryani spices"],
        "Roast": [main, "garlic", "black pepper", "soy sauce"],
        "Soup (Kool)": [main, "coconut milk", "tamarind", "chili"],
        "Cutlet": [main, "potato", "bread crumbs", "egg"],
        "Fried": [main, "turmeric", "chili powder", "curry leaves"],
        "Wade": [main, "onion", "green chili", "curry leaves"],
        "Roll": [main, "flour crepe", "bread crumbs", "carrot"],
        "Sambol": [main, "grated coconut", "chili", "lime juice", "onion"],
        "Curry-Veg": [main, "coconut milk", "turmeric", "mustard seeds", "curry leaves"],
        "Black Curry (Kalu Pol)": [main, "roasted coconut", "roasted curry powder", "garlic"],
        "White Curry (Kiri Hodi)": [main, "coconut milk", "green chili", "curry leaves"],
        "Tempered (Thel Dala)": [main, "mustard seeds", "dried chili", "onion", "curry leaves"],
        "Moju": [main, "vinegar", "sugar", "mustard seeds", "dried chili"],
        "Achcharu (Pickle)": [main, "vinegar", "chili", "mustard"],
        "Mallung": [main, "grated coconut", "turmeric", "onion", "green chili"],
        "Rice/Grain": ["rice", "coconut milk", "spices"],
        "Bread/Hopper": ["rice flour", "coconut milk", "yeast"],
        "Short Eats": [main, "flour", "spices"],
        "Dessert": ["rice flour", "kithul treacle", "coconut milk"],
        "Breakfast Porridge": ["rice", "herbs", "coconut milk"],
        "Beverage": [main],
    }
    return base.get(style, [main, "spices"])


def style_key(style_name):
    """Map a human style label to a profile key."""
    mapping = {
        "Curry": None,  # resolved per protein/veg below
        "Black Curry (Kalu Pol)": "Black Curry (Kalu Pol)",
        "White Curry (Kiri Hodi)": "White Curry (Kiri Hodi)",
        "Devilled": "Devilled",
        "Ambul Thiyal": "Ambul Thiyal",
        "Kottu": "Kottu",
        "Fried Rice": "Fried Rice",
        "Biryani": "Biryani",
        "Roast": "Roast",
        "Soup (Kool)": "Soup (Kool)",
        "Cutlet": "Cutlet",
        "Fried": "Fried",
        "Wade": "Wade",
        "Roll": "Roll",
        "Sambol": "Sambol",
        "Tempered (Thel Dala)": "Tempered (Thel Dala)",
        "Moju": "Moju",
        "Achcharu (Pickle)": "Achcharu (Pickle)",
        "Mallung": "Mallung",
    }
    return mapping.get(style_name, style_name)


def add_recipe(name, category, main, dietary, meal_type, spice, profile_key, servings_range=(2, 4), prep_range=(10, 20), cook_range=(15, 40)):
    lo = profiles[profile_key]
    cal = round(random.uniform(lo[0], lo[1]))
    prot = round(random.uniform(lo[2], lo[3]), 1)
    carb = round(random.uniform(lo[4], lo[5]), 1)
    fat = round(random.uniform(lo[6], lo[7]), 1)
    fiber = round(random.uniform(lo[8], lo[9]), 1)
    prep = random.randint(*prep_range)
    cook = random.randint(*cook_range)
    servings = random.randint(*servings_range)
    ingredients = ", ".join(key_ingredients(main, profile_key)[:5])
    desc = f"{name.split('(')[0].strip()} - {random.choice(descriptors)}"
    recipes.append({
        "Recipe_Name": name,
        "Category": category,
        "Main_Ingredient": main,
        "Dietary_Tag": dietary,
        "Meal_Type": meal_type,
        "Spice_Level": spice,
        "Calories_kcal": cal,
        "Protein_g": prot,
        "Carbs_g": carb,
        "Fat_g": fat,
        "Fiber_g": fiber,
        "Prep_Time_Min": prep,
        "Cook_Time_Min": cook,
        "Servings": servings,
        "Key_Ingredients": ingredients,
        "Short_Description": desc,
    })


# ---------------------------------------------------------------
# 1. Protein-based dishes
# ---------------------------------------------------------------
PROTEIN_STYLE_PROFILE = {
    "Curry": "Curry-Protein",
    "Black Curry (Kalu Pol)": "Curry-Protein-Black",
    "White Curry (Kiri Hodi)": "Curry-Protein-White",
    "Devilled": "Devilled",
    "Ambul Thiyal": "Ambul Thiyal",
    "Kottu": "Kottu",
    "Fried Rice": "Fried Rice",
    "Biryani": "Biryani",
    "Roast": "Roast",
    "Soup (Kool)": "Soup (Kool)",
    "Cutlet": "Cutlet",
    "Fried": "Fried",
    "Wade": "Wade",
    "Roll": "Roll",
    "Sambol": "Sambol",
    "Tempered (Thel Dala)": "Tempered (Thel Dala)",
}

for protein, (dietary, styles) in proteins.items():
    for style in styles:
        pkey = PROTEIN_STYLE_PROFILE[style]
        display_style = style
        name = f"{protein.split('(')[0].strip()} {display_style}"
        meal_type = "Snack" if pkey in ("Cutlet", "Wade", "Roll", "Sambol") else random.choice(["Lunch", "Dinner"])
        spice = random.choice(["Mild", "Medium", "Medium", "Hot"])
        add_recipe(name, display_style, protein, dietary, meal_type, spice, pkey)

# ---------------------------------------------------------------
# 2. Vegetable curries
# ---------------------------------------------------------------
for veg, styles in veggies.items():
    for style in styles:
        if style == "Curry":
            pkey = "Curry-Veg"
        else:
            pkey = style_key(style)
        name = f"{veg.split('(')[0].strip()} {style}"
        meal_type = random.choice(["Lunch", "Dinner"])
        spice = random.choice(["Mild", "Medium", "Medium", "Hot"])
        add_recipe(name, style, veg, "Vegan", meal_type, spice, pkey, prep_range=(10, 15), cook_range=(15, 30))

# ---------------------------------------------------------------
# 3. Leafy greens
# ---------------------------------------------------------------
for green, styles in leafy.items():
    for style in styles:
        pkey = style_key(style) if style != "Curry" else "Curry-Veg"
        name = f"{green.split('(')[0].strip()} {style}"
        add_recipe(name, style, green, "Vegan", random.choice(["Lunch", "Dinner"]),
                   random.choice(["Mild", "Medium"]), pkey, prep_range=(8, 15), cook_range=(10, 20))

# ---------------------------------------------------------------
# 4. Sambols
# ---------------------------------------------------------------
for s in sambols:
    main = s.split("(")[0].strip()
    add_recipe(s, "Sambol", main, "Vegan" if "Sprats" not in s and "Karawala" not in s else "Pescatarian",
               "Snack", random.choice(["Medium", "Hot"]), "Sambol", servings_range=(3, 6), prep_range=(5, 10), cook_range=(0, 5))

# ---------------------------------------------------------------
# 5. Rice & grain dishes
# ---------------------------------------------------------------
for r in rice_grain:
    dietary = "Vegetarian" if "Vegetable" in r or "Yellow" in r or "Ghee" in r or "Kiribath" in r or "Red Rice" in r or "String" in r else "Non-Vegetarian"
    add_recipe(r, "Rice & Grain", "Rice", dietary, random.choice(["Lunch", "Dinner"]),
               random.choice(["Mild", "Medium"]), "Rice/Grain", servings_range=(3, 6), prep_range=(15, 30), cook_range=(30, 60))

# ---------------------------------------------------------------
# 6. Bread & hoppers
# ---------------------------------------------------------------
for b in bread_hoppers:
    dietary = "Vegetarian" if "Egg" in b else "Vegan"
    add_recipe(b, "Bread & Hoppers", "Rice Flour", dietary, "Breakfast",
               "Mild", "Bread/Hopper", servings_range=(1, 3), prep_range=(15, 30), cook_range=(10, 20))

# ---------------------------------------------------------------
# 7. Short eats
# ---------------------------------------------------------------
for se in short_eats:
    main = "Fish" if "Fish" in se else "Chicken" if "Chicken" in se else "Lentil" if ("Wade" in se and "Isso" not in se) else "Vegetable"
    dietary = "Pescatarian" if "Fish" in se or "Isso" in se else "Non-Vegetarian" if "Chicken" in se else "Vegetarian"
    add_recipe(se, "Short Eats", main, dietary, "Snack", random.choice(["Mild", "Medium"]),
               "Short Eats", servings_range=(4, 8), prep_range=(20, 35), cook_range=(10, 20))

# ---------------------------------------------------------------
# 8. Desserts
# ---------------------------------------------------------------
for d in desserts:
    add_recipe(d, "Dessert", "Rice Flour/Coconut", "Vegetarian", "Snack",
               "Mild", "Dessert", servings_range=(4, 8), prep_range=(20, 40), cook_range=(20, 45))

# ---------------------------------------------------------------
# 9. Breakfast porridge
# ---------------------------------------------------------------
for bp in breakfast_porridge:
    add_recipe(bp, "Breakfast", "Rice/Grain", "Vegan", "Breakfast", "Mild",
               "Breakfast Porridge", servings_range=(1, 2), prep_range=(5, 10), cook_range=(15, 25))

# ---------------------------------------------------------------
# 10. Beverages
# ---------------------------------------------------------------
for bv in beverages:
    add_recipe(bv, "Beverage", bv, "Vegan", "Snack", "Mild", "Beverage",
               servings_range=(1, 2), prep_range=(5, 10), cook_range=(0, 5))

# ---------------------------------------------------------------
# Dedup by name, then pad with regional variants of popular curries if under 300
# ---------------------------------------------------------------
seen = set()
unique_recipes = []
for r in recipes:
    if r["Recipe_Name"] not in seen:
        seen.add(r["Recipe_Name"])
        unique_recipes.append(r)

print(f"Base unique recipes generated: {len(unique_recipes)}")

# Pad with regional / house-style variants if still short of 300.
# Combine a wide modifier pool with every protein AND vegetable so the
# combinatorial space comfortably exceeds 300 unique names.
if len(unique_recipes) < 300:
    modifiers = ["Jaffna-style ", "Negombo-style ", "Kandyan-style ", "Southern-style ",
                 "Traditional ", "Homestyle ", "Village-style ", "Coastal ",
                 "Grandma's ", "Classic ", "Estate-style ", "Low-Country "]

    padding_mains = []
    for protein, (dietary, _styles) in proteins.items():
        padding_mains.append((protein, dietary, "Curry-Protein", "Non-Veg/Seafood"))
    for veg in veggies:
        padding_mains.append((veg, "Vegan", "Curry-Veg", "Vegetable"))
    for green in leafy:
        padding_mains.append((green, "Vegan", "Mallung", "Leafy Green"))

    combo_list = [(m, main, dietary, pkey, kind)
                  for m in modifiers
                  for (main, dietary, pkey, kind) in padding_mains]
    random.shuffle(combo_list)

    for region, main, dietary, pkey, kind in combo_list:
        if len(unique_recipes) >= 300:
            break
        suffix = "Curry" if pkey != "Mallung" else "Mallung"
        base_name = f"{main.split('(')[0].strip()} {suffix}"
        name = f"{region}{base_name}"
        if name in seen:
            continue
        seen.add(name)
        add_recipe(name, suffix, main, dietary, random.choice(["Lunch", "Dinner"]),
                   random.choice(["Mild", "Medium", "Hot"]), pkey)
        unique_recipes.append(recipes[-1])

# Trim to exactly 300 if over
unique_recipes = unique_recipes[:300]
print(f"Final recipe count: {len(unique_recipes)}")

# ---------------------------------------------------------------
# Assign IDs and food group
# ---------------------------------------------------------------
FOOD_GROUP_MAP = {
    "Curry": "Rice & Curry", "Black Curry (Kalu Pol)": "Rice & Curry",
    "White Curry (Kiri Hodi)": "Rice & Curry", "Devilled": "Rice & Curry",
    "Ambul Thiyal": "Rice & Curry", "Tempered (Thel Dala)": "Rice & Curry",
    "Moju": "Rice & Curry", "Achcharu (Pickle)": "Rice & Curry",
    "Mallung": "Rice & Curry", "Roast": "Rice & Curry",
    "Kottu": "One-Pot / Rice Dish", "Fried Rice": "One-Pot / Rice Dish",
    "Biryani": "One-Pot / Rice Dish", "Rice/Grain": "One-Pot / Rice Dish",
    "Rice & Grain": "One-Pot / Rice Dish",
    "Soup (Kool)": "Soup",
    "Sambol": "Condiment / Sambol",
    "Cutlet": "Short Eats", "Fried": "Short Eats", "Wade": "Short Eats",
    "Roll": "Short Eats", "Short Eats": "Short Eats",
    "Bread & Hoppers": "Bread & Hoppers",
    "Dessert": "Dessert", "Breakfast": "Breakfast Porridge", "Beverage": "Beverage",
}

for i, r in enumerate(unique_recipes, start=1):
    r["Recipe_ID"] = f"SL{i:03d}"
    r["Food_Group"] = FOOD_GROUP_MAP.get(r["Category"], "Rice & Curry")

import json
import os
os.makedirs("data", exist_ok=True)
with open("data/recipes.json", "w") as f:
    json.dump(unique_recipes, f, indent=2)

print("Saved data/recipes.json")

cats = {}
for r in unique_recipes:
    cats[r["Category"]] = cats.get(r["Category"], 0) + 1
for k, v in sorted(cats.items(), key=lambda x: -x[1]):
    print(f"  {k}: {v}")
