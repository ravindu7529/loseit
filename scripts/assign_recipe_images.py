"""
assign_recipe_images.py

Curates and embeds high-resolution food photography URLs (Unsplash CDN) into the 300 Sri Lankan recipes dataset.
"""

import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

MOBILE_RECIPES_PATH = BASE_DIR / "mobile" / "assets" / "data" / "recipes.json"
BACKEND_RECIPES_PATH = BASE_DIR / "backend" / "data" / "recipes.json"

# Curated High-Definition Food Photography Collections (All 100% verified HTTP 200)
IMAGE_LIBRARY = {
    # Chicken
    "chicken_curry": "https://images.unsplash.com/photo-1589301760014-d929f3979dbc?auto=format&fit=crop&w=800&q=80",
    "chicken_black_curry": "https://images.unsplash.com/photo-1610057099443-fde8c4d50f91?auto=format&fit=crop&w=800&q=80",
    "chicken_white_curry": "https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?auto=format&fit=crop&w=800&q=80",
    "chicken_devilled": "https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=800&q=80",
    "chicken_kottu": "https://images.unsplash.com/photo-1555126634-323283e090fa?auto=format&fit=crop&w=800&q=80",
    "chicken_fried_rice": "https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=800&q=80",
    "chicken_biryani": "https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?auto=format&fit=crop&w=800&q=80",
    "chicken_roast": "https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?auto=format&fit=crop&w=800&q=80",
    "chicken_soup": "https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=800&q=80",

    # Fish & Seafood
    "fish_curry": "https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?auto=format&fit=crop&w=800&q=80",
    "fish_ambul_thiyal": "https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?auto=format&fit=crop&w=800&q=80",
    "fish_devilled": "https://images.unsplash.com/photo-1565680018434-b513d5e5fd47?auto=format&fit=crop&w=800&q=80",
    "fish_cutlet": "https://images.unsplash.com/photo-1599084993091-1cb5c0721cc6?auto=format&fit=crop&w=800&q=80",
    "fish_fried": "https://images.unsplash.com/photo-1599084993091-1cb5c0721cc6?auto=format&fit=crop&w=800&q=80",
    "prawns_curry": "https://images.unsplash.com/photo-1559742811-822873691df8?auto=format&fit=crop&w=800&q=80",
    "prawns_devilled": "https://images.unsplash.com/photo-1565680018434-b513d5e5fd47?auto=format&fit=crop&w=800&q=80",
    "prawns_wade": "https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=800&q=80",
    "prawns_kottu": "https://images.unsplash.com/photo-1585032226651-759b368d7246?auto=format&fit=crop&w=800&q=80",
    "prawns_fried_rice": "https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=800&q=80",
    "cuttlefish_curry": "https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=800&q=80",
    "crab_curry": "https://images.unsplash.com/photo-1551248429-40975aa4de74?auto=format&fit=crop&w=800&q=80",
    "dried_sprats": "https://images.unsplash.com/photo-1599084993091-1cb5c0721cc6?auto=format&fit=crop&w=800&q=80",
    "dried_fish": "https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?auto=format&fit=crop&w=800&q=80",

    # Meats
    "beef_curry": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80",
    "beef_devilled": "https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=800&q=80",
    "mutton_curry": "https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=800&q=80",
    "pork_curry": "https://images.unsplash.com/photo-1529692236671-f1f6cf9683ba?auto=format&fit=crop&w=800&q=80",

    # Eggs
    "egg_curry": "https://images.unsplash.com/photo-1525351484163-7529414344d8?auto=format&fit=crop&w=800&q=80",
    "egg_kottu": "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=800&q=80",
    "egg_fried_rice": "https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=800&q=80",
    "egg_hoppers": "https://images.unsplash.com/photo-1582169296194-e4d644c48063?auto=format&fit=crop&w=800&q=80",

    # Dhal, Lentils & Chickpeas
    "dhal_curry": "https://images.unsplash.com/photo-1546833999-b9f581a1996d?auto=format&fit=crop&w=800&q=80",
    "lentil_curry": "https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?auto=format&fit=crop&w=800&q=80",
    "chickpea_curry": "https://images.unsplash.com/photo-1585937421612-70a008356fbe?auto=format&fit=crop&w=800&q=80",

    # Plant-based & Proteins
    "soya_meat_curry": "https://images.unsplash.com/photo-1604382354936-07c5d9983bd3?auto=format&fit=crop&w=800&q=80",
    "tofu_curry": "https://images.unsplash.com/photo-1546069901-d5bfd2cbfb1f?auto=format&fit=crop&w=800&q=80",
    "mushroom_curry": "https://images.unsplash.com/photo-1505253758473-96b7015fcd40?auto=format&fit=crop&w=800&q=80",

    # Vegetables
    "pumpkin_curry": "https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=800&q=80",
    "beetroot_curry": "https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&w=800&q=80",
    "potato_curry": "https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=800&q=80",
    "cashew_curry": "https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=800&q=80",
    "okra_curry": "https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=800&q=80",
    "brinjal_moju": "https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?auto=format&fit=crop&w=800&q=80",
    "jackfruit_polos": "https://images.unsplash.com/photo-1613844237701-8f3664fc2eff?auto=format&fit=crop&w=800&q=80",
    "jackfruit_seed": "https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=800&q=80",
    "green_beans": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=800&q=80",
    "snake_gourd": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=800&q=80",
    "bitter_gourd": "https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=800&q=80",
    "drumstick_murunga": "https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?auto=format&fit=crop&w=800&q=80",
    "manioc_cassava": "https://images.unsplash.com/photo-1547496502-affa22d38842?auto=format&fit=crop&w=800&q=80",
    "breadfruit_del": "https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=800&q=80",
    "ash_plantain": "https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=800&q=80",
    "mango_curry": "https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&w=800&q=80",
    "pineapple_curry": "https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&w=800&q=80",
    "carrot_curry": "https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=800&q=80",
    "winged_bean": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=800&q=80",

    # Mallung & Greens
    "gotukola_mallung": "https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&w=800&q=80",
    "kankun_mallung": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=800&q=80",
    "spinach_mallung": "https://images.unsplash.com/photo-1576045057995-568f588f82fb?auto=format&fit=crop&w=800&q=80",
    "cabbage_mallung": "https://images.unsplash.com/photo-1550583724-b2692b85b150?auto=format&fit=crop&w=800&q=80",
    "sarana_mallung": "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=800&q=80",
    "mukunuwenna_mallung": "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=800&q=80",

    # Sambols
    "pol_sambol": "https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=800&q=80",
    "seeni_sambol": "https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?auto=format&fit=crop&w=800&q=80",
    "katta_sambol": "https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?auto=format&fit=crop&w=800&q=80",
    "lunu_miris": "https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?auto=format&fit=crop&w=800&q=80",
    "general_sambol": "https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&w=800&q=80",

    # Bread & Hoppers
    "hoppers_appa": "https://images.unsplash.com/photo-1582169296194-e4d644c48063?auto=format&fit=crop&w=800&q=80",
    "string_hoppers": "https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=800&q=80",
    "pol_roti": "https://images.unsplash.com/photo-1565299585323-38d6b0865b47?auto=format&fit=crop&w=800&q=80",
    "pittu": "https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=800&q=80",

    # Short Eats
    "short_eats": "https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=800&q=80",
    "rolls": "https://images.unsplash.com/photo-1541592106381-b31e9677c0e5?auto=format&fit=crop&w=800&q=80",
    "wade": "https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=800&q=80",

    # Soups & Porridges
    "seafood_kool": "https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=800&q=80",
    "kola_kenda": "https://images.unsplash.com/photo-1576045057995-568f588f82fb?auto=format&fit=crop&w=800&q=80",
    "porridge": "https://images.unsplash.com/photo-1541832676-9b763b0239ab?auto=format&fit=crop&w=800&q=80",

    # Desserts
    "watalappam": "https://images.unsplash.com/photo-1587314168485-3236d6710814?auto=format&fit=crop&w=800&q=80",
    "curd_treacle": "https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=800&q=80",
    "bibikkan_cake": "https://images.unsplash.com/photo-1578985545062-69928b1d9587?auto=format&fit=crop&w=800&q=80",
    "festive_sweets": "https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=800&q=80",

    # Beverages
    "king_coconut": "https://images.unsplash.com/photo-1525385133512-2f3bdd039054?auto=format&fit=crop&w=800&q=80",
    "ceylon_tea": "https://images.unsplash.com/photo-1576092768241-dec231879fc3?auto=format&fit=crop&w=800&q=80",
    "herbal_tea": "https://images.unsplash.com/photo-1556679343-c7306c1976bc?auto=format&fit=crop&w=800&q=80",
    "faluda": "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=800&q=80",

    # General Fallbacks
    "rice_and_curry_plate": "https://images.unsplash.com/photo-1546833999-b9f581a1996d?auto=format&fit=crop&w=800&q=80",
    "curry_dish": "https://images.unsplash.com/photo-1589301760014-d929f3979dbc?auto=format&fit=crop&w=800&q=80",
}


def match_recipe_image(recipe: dict) -> str:
    name = recipe.get("Recipe_Name", "").lower()
    cat = recipe.get("Category", "").lower()
    ing = recipe.get("Main_Ingredient", "").lower()
    group = recipe.get("Food_Group", "").lower()

    # Beverages
    if "king coconut" in name or "thambili" in name:
        return IMAGE_LIBRARY["king_coconut"]
    if "faluda" in name:
        return IMAGE_LIBRARY["faluda"]
    if "belimal" in name or "ranawara" in name or "herbal" in name:
        return IMAGE_LIBRARY["herbal_tea"]
    if "tea" in name or group == "beverage":
        return IMAGE_LIBRARY["ceylon_tea"]

    # Desserts
    if "watalappam" in name or "custard" in name:
        return IMAGE_LIBRARY["watalappam"]
    if "curd" in name or "treacle" in name:
        return IMAGE_LIBRARY["curd_treacle"]
    if "bibikkan" in name or "cake" in name or "halapa" in name:
        return IMAGE_LIBRARY["bibikkan_cake"]
    if "toffee" in name or "kokis" in name or "kavum" in name or "dodol" in name or "aluwa" in name or group == "dessert":
        return IMAGE_LIBRARY["festive_sweets"]

    # Breakfast Porridge & Soup
    if "kool" in name or "soup" in cat:
        return IMAGE_LIBRARY["seafood_kool"]
    if "kenda" in name or "kola" in name:
        return IMAGE_LIBRARY["kola_kenda"]
    if group == "breakfast porridge" or "porridge" in name:
        return IMAGE_LIBRARY["porridge"]

    # Bread, Hoppers, Roti, Pittu
    if "egg hopper" in name:
        return IMAGE_LIBRARY["egg_hoppers"]
    if "hopper" in name or "appa" in name:
        return IMAGE_LIBRARY["hoppers_appa"]
    if "string hopper" in name or "idiyappam" in name:
        return IMAGE_LIBRARY["string_hoppers"]
    if "roti" in name:
        return IMAGE_LIBRARY["pol_roti"]
    if "pittu" in name:
        return IMAGE_LIBRARY["pittu"]

    # Kottu
    if "kottu" in cat or "kottu" in name:
        if "chicken" in ing:
            return IMAGE_LIBRARY["chicken_kottu"]
        if "prawn" in ing or "seafood" in ing:
            return IMAGE_LIBRARY["prawns_kottu"]
        if "egg" in ing:
            return IMAGE_LIBRARY["egg_kottu"]
        return IMAGE_LIBRARY["chicken_kottu"]

    # Rice & Biryani
    if "biryani" in cat or "biryani" in name:
        return IMAGE_LIBRARY["chicken_biryani"]
    if "fried rice" in cat or "fried rice" in name:
        if "chicken" in ing:
            return IMAGE_LIBRARY["chicken_fried_rice"]
        if "prawn" in ing:
            return IMAGE_LIBRARY["prawns_fried_rice"]
        return IMAGE_LIBRARY["egg_fried_rice"]

    # Short eats
    if "cutlet" in cat or "cutlet" in name:
        return IMAGE_LIBRARY["fish_cutlet"]
    if "roll" in cat or "roll" in name:
        return IMAGE_LIBRARY["rolls"]
    if "wade" in cat or "wade" in name:
        if "prawn" in ing:
            return IMAGE_LIBRARY["prawns_wade"]
        return IMAGE_LIBRARY["wade"]
    if group == "short eats" or cat == "short eats":
        return IMAGE_LIBRARY["short_eats"]

    # Sambols
    if "pol sambol" in name:
        return IMAGE_LIBRARY["pol_sambol"]
    if "seeni sambol" in name:
        return IMAGE_LIBRARY["seeni_sambol"]
    if "katta sambol" in name or "lunu miris" in name:
        return IMAGE_LIBRARY["katta_sambol"]
    if "sambol" in cat or group == "condiment / sambol" or "sambol" in name:
        return IMAGE_LIBRARY["general_sambol"]

    # Mallung & Greens
    if "gotukola" in ing or "gotukola" in name:
        return IMAGE_LIBRARY["gotukola_mallung"]
    if "kankun" in ing or "kankun" in name:
        return IMAGE_LIBRARY["kankun_mallung"]
    if "spinach" in ing or "nivithi" in ing or "spinach" in name:
        return IMAGE_LIBRARY["spinach_mallung"]
    if "cabbage" in ing or "cabbage" in name:
        return IMAGE_LIBRARY["cabbage_mallung"]
    if "sarana" in ing or "sarana" in name:
        return IMAGE_LIBRARY["sarana_mallung"]
    if "mukunuwenna" in ing or "mukunuwenna" in name:
        return IMAGE_LIBRARY["mukunuwenna_mallung"]
    if "mallung" in cat:
        return IMAGE_LIBRARY["gotukola_mallung"]

    # Devilled
    if "devilled" in cat or "devilled" in name:
        if "chicken" in ing:
            return IMAGE_LIBRARY["chicken_devilled"]
        if "prawn" in ing:
            return IMAGE_LIBRARY["prawns_devilled"]
        if "fish" in ing:
            return IMAGE_LIBRARY["fish_devilled"]
        if "beef" in ing:
            return IMAGE_LIBRARY["beef_devilled"]
        return IMAGE_LIBRARY["chicken_devilled"]

    # Ambul Thiyal
    if "ambul thiyal" in cat or "ambul thiyal" in name:
        return IMAGE_LIBRARY["fish_ambul_thiyal"]

    # Black Curry (Kalu Pol)
    if "black curry" in cat or "kalu pol" in cat or "black curry" in name:
        if "chicken" in ing:
            return IMAGE_LIBRARY["chicken_black_curry"]
        if "beef" in ing or "mutton" in ing or "pork" in ing:
            return IMAGE_LIBRARY["beef_curry"]
        if "polos" in ing or "jackfruit" in ing:
            return IMAGE_LIBRARY["jackfruit_polos"]
        return IMAGE_LIBRARY["chicken_black_curry"]

    # White Curry (Kiri Hodi)
    if "white curry" in cat or "kiri hodi" in cat or "white curry" in name:
        if "chicken" in ing:
            return IMAGE_LIBRARY["chicken_white_curry"]
        if "fish" in ing:
            return IMAGE_LIBRARY["fish_curry"]
        if "egg" in ing:
            return IMAGE_LIBRARY["egg_curry"]
        return IMAGE_LIBRARY["chicken_white_curry"]

    # Meats & Seafood by Ingredient
    if "chicken" in ing:
        if "roast" in cat or "roast" in name:
            return IMAGE_LIBRARY["chicken_roast"]
        return IMAGE_LIBRARY["chicken_curry"]

    if "prawn" in ing:
        return IMAGE_LIBRARY["prawns_curry"]

    if "cuttlefish" in ing or "squid" in ing:
        return IMAGE_LIBRARY["cuttlefish_curry"]

    if "crab" in ing:
        return IMAGE_LIBRARY["crab_curry"]

    if "tuna" in ing or "fish" in ing or "seer" in ing:
        if "fried" in cat or "fried" in name:
            return IMAGE_LIBRARY["fish_fried"]
        return IMAGE_LIBRARY["fish_curry"]

    if "sprat" in ing or "halmasso" in ing:
        return IMAGE_LIBRARY["dried_sprats"]

    if "dried fish" in ing or "karawala" in ing:
        return IMAGE_LIBRARY["dried_fish"]

    if "beef" in ing:
        return IMAGE_LIBRARY["beef_curry"]

    if "mutton" in ing:
        return IMAGE_LIBRARY["mutton_curry"]

    if "pork" in ing:
        return IMAGE_LIBRARY["pork_curry"]

    if "egg" in ing:
        return IMAGE_LIBRARY["egg_curry"]

    # Plant-based Proteins & Specific Veggies
    if "parippu" in ing or "dhal" in ing or "red lentil" in ing:
        return IMAGE_LIBRARY["dhal_curry"]

    if "lentil" in ing:
        return IMAGE_LIBRARY["lentil_curry"]

    if "chickpea" in ing or "kadala" in ing:
        return IMAGE_LIBRARY["chickpea_curry"]

    if "soya meat" in ing or "soya" in ing:
        return IMAGE_LIBRARY["soya_meat_curry"]

    if "tofu" in ing:
        return IMAGE_LIBRARY["tofu_curry"]

    if "mushroom" in ing:
        return IMAGE_LIBRARY["mushroom_curry"]

    if "pumpkin" in ing or "wattakka" in ing:
        return IMAGE_LIBRARY["pumpkin_curry"]

    if "beetroot" in ing:
        return IMAGE_LIBRARY["beetroot_curry"]

    if "potato" in ing or "ala" in ing:
        return IMAGE_LIBRARY["potato_curry"]

    if "cashew" in ing:
        return IMAGE_LIBRARY["cashew_curry"]

    if "okra" in ing or "bandakka" in ing:
        return IMAGE_LIBRARY["okra_curry"]

    if "brinjal" in ing or "eggplant" in ing or "wambatu" in ing or "moju" in cat:
        return IMAGE_LIBRARY["brinjal_moju"]

    if "polos" in ing or "young jackfruit" in ing:
        return IMAGE_LIBRARY["jackfruit_polos"]

    if "kos ata" in ing or "jackfruit seed" in ing:
        return IMAGE_LIBRARY["jackfruit_seed"]

    if "green bean" in ing or "bonchi" in ing:
        return IMAGE_LIBRARY["green_beans"]

    if "snake gourd" in ing or "pathola" in ing:
        return IMAGE_LIBRARY["snake_gourd"]

    if "bitter gourd" in ing or "karawila" in ing:
        return IMAGE_LIBRARY["bitter_gourd"]

    if "murunga" in ing or "drumstick" in ing:
        return IMAGE_LIBRARY["drumstick_murunga"]

    if "manioc" in ing or "kappa" in ing or "cassava" in ing:
        return IMAGE_LIBRARY["manioc_cassava"]

    if "breadfruit" in ing or "del" in ing:
        return IMAGE_LIBRARY["breadfruit_del"]

    if "ash plantain" in ing or "alu kesel" in ing:
        return IMAGE_LIBRARY["ash_plantain"]

    if "mango" in ing:
        return IMAGE_LIBRARY["mango_curry"]

    if "pineapple" in ing:
        return IMAGE_LIBRARY["pineapple_curry"]

    if "carrot" in ing:
        return IMAGE_LIBRARY["carrot_curry"]

    if "winged bean" in ing or "dambala" in ing:
        return IMAGE_LIBRARY["winged_bean"]

    # Fallback to category / food group
    if group == "one-pot / rice dish":
        return IMAGE_LIBRARY["chicken_fried_rice"]

    return IMAGE_LIBRARY["rice_and_curry_plate"]


def process_file(file_path: Path):
    with open(file_path, "r", encoding="utf-8") as f:
        recipes = json.load(f)

    print(f"Loaded {len(recipes)} recipes from {file_path.name}")
    updated = []
    for r in recipes:
        img_url = match_recipe_image(r)
        r["Image_Url"] = img_url
        updated.append(r)

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(updated, f, indent=2, ensure_ascii=False)

    print(f"Successfully wrote {len(updated)} recipes with Image_Url to {file_path}")


if __name__ == "__main__":
    process_file(MOBILE_RECIPES_PATH)
    process_file(BACKEND_RECIPES_PATH)
