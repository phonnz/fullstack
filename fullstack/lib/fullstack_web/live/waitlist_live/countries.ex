defmodule FullstackWeb.WaitlistLive.Countries do
  @moduledoc """
  Static country list for the waitlist signup form's country dropdown.

  Hardcoded on purpose (no new dependency) — see
  `odd/tasks/waitlist-landing-page.md` for the decision record. The first
  entry, `"I don't know yet"`, is the form's default/blank option and is
  mapped to `nil` before the signup is persisted.
  """

  @default "I don't know yet"

  @countries [
    "Afghanistan",
    "Albania",
    "Algeria",
    "Andorra",
    "Angola",
    "Antigua and Barbuda",
    "Argentina",
    "Armenia",
    "Australia",
    "Austria",
    "Azerbaijan",
    "Bahamas",
    "Bahrain",
    "Bangladesh",
    "Barbados",
    "Belarus",
    "Belgium",
    "Belize",
    "Benin",
    "Bhutan",
    "Bolivia",
    "Bosnia and Herzegovina",
    "Botswana",
    "Brazil",
    "Brunei",
    "Bulgaria",
    "Burkina Faso",
    "Burundi",
    "Cabo Verde",
    "Cambodia",
    "Cameroon",
    "Canada",
    "Central African Republic",
    "Chad",
    "Chile",
    "China",
    "Colombia",
    "Comoros",
    "Congo (Brazzaville)",
    "Congo (Kinshasa)",
    "Costa Rica",
    "Croatia",
    "Cuba",
    "Cyprus",
    "Czechia",
    "Denmark",
    "Djibouti",
    "Dominica",
    "Dominican Republic",
    "Ecuador",
    "Egypt",
    "El Salvador",
    "Equatorial Guinea",
    "Eritrea",
    "Estonia",
    "Eswatini",
    "Ethiopia",
    "Fiji",
    "Finland",
    "France",
    "Gabon",
    "Gambia",
    "Georgia",
    "Germany",
    "Ghana",
    "Greece",
    "Grenada",
    "Guatemala",
    "Guinea",
    "Guinea-Bissau",
    "Guyana",
    "Haiti",
    "Honduras",
    "Hungary",
    "Iceland",
    "India",
    "Indonesia",
    "Iran",
    "Iraq",
    "Ireland",
    "Israel",
    "Italy",
    "Jamaica",
    "Japan",
    "Jordan",
    "Kazakhstan",
    "Kenya",
    "Kiribati",
    "Kosovo",
    "Kuwait",
    "Kyrgyzstan",
    "Laos",
    "Latvia",
    "Lebanon",
    "Lesotho",
    "Liberia",
    "Libya",
    "Liechtenstein",
    "Lithuania",
    "Luxembourg",
    "Madagascar",
    "Malawi",
    "Malaysia",
    "Maldives",
    "Mali",
    "Malta",
    "Marshall Islands",
    "Mauritania",
    "Mauritius",
    "Mexico",
    "Micronesia",
    "Moldova",
    "Monaco",
    "Mongolia",
    "Montenegro",
    "Morocco",
    "Mozambique",
    "Myanmar",
    "Namibia",
    "Nauru",
    "Nepal",
    "Netherlands",
    "New Zealand",
    "Nicaragua",
    "Niger",
    "Nigeria",
    "North Korea",
    "North Macedonia",
    "Norway",
    "Oman",
    "Pakistan",
    "Palau",
    "Palestine",
    "Panama",
    "Papua New Guinea",
    "Paraguay",
    "Peru",
    "Philippines",
    "Poland",
    "Portugal",
    "Qatar",
    "Romania",
    "Russia",
    "Rwanda",
    "Saint Kitts and Nevis",
    "Saint Lucia",
    "Saint Vincent and the Grenadines",
    "Samoa",
    "San Marino",
    "Sao Tome and Principe",
    "Saudi Arabia",
    "Senegal",
    "Serbia",
    "Seychelles",
    "Sierra Leone",
    "Singapore",
    "Slovakia",
    "Slovenia",
    "Solomon Islands",
    "Somalia",
    "South Africa",
    "South Korea",
    "South Sudan",
    "Spain",
    "Sri Lanka",
    "Sudan",
    "Suriname",
    "Sweden",
    "Switzerland",
    "Syria",
    "Taiwan",
    "Tajikistan",
    "Tanzania",
    "Thailand",
    "Timor-Leste",
    "Togo",
    "Tonga",
    "Trinidad and Tobago",
    "Tunisia",
    "Turkey",
    "Turkmenistan",
    "Tuvalu",
    "Uganda",
    "Ukraine",
    "United Arab Emirates",
    "United Kingdom",
    "United States",
    "Uruguay",
    "Uzbekistan",
    "Vanuatu",
    "Vatican City",
    "Venezuela",
    "Vietnam",
    "Yemen",
    "Zambia",
    "Zimbabwe",
    "American Samoa",
    "Anguilla",
    "Aruba",
    "Bermuda",
    "Bonaire, Sint Eustatius and Saba",
    "British Virgin Islands",
    "Cayman Islands",
    "Christmas Island",
    "Cocos (Keeling) Islands",
    "Cook Islands",
    "Curacao",
    "Falkland Islands",
    "Faroe Islands",
    "French Guiana",
    "French Polynesia",
    "Gibraltar",
    "Greenland",
    "Guadeloupe",
    "Guam",
    "Guernsey",
    "Hong Kong",
    "Isle of Man",
    "Jersey",
    "Macau",
    "Martinique",
    "Mayotte",
    "Montserrat",
    "New Caledonia",
    "Niue",
    "Norfolk Island",
    "Northern Mariana Islands",
    "Puerto Rico",
    "Reunion",
    "Saint Barthelemy",
    "Saint Helena",
    "Saint Martin",
    "Saint Pierre and Miquelon",
    "Sint Maarten",
    "Tokelau",
    "Turks and Caicos Islands",
    "U.S. Virgin Islands",
    "Wallis and Futuna",
    "Western Sahara"
  ]

  @doc """
  The default option shown in the country dropdown before a selection is
  made. Selecting (or keeping) this option means "unknown country" and must
  be persisted as `nil`, never as this literal string.
  """
  def default, do: @default

  @doc """
  Returns the `{label, value}` pairs for the country `<select>`, with the
  default "unknown country" option first.

  ## Examples

      iex> [{"I don't know yet", "I don't know yet"} | _] = FullstackWeb.WaitlistLive.Countries.options()

  """
  def options do
    for country <- [@default | @countries], do: {country, country}
  end

  @doc """
  Normalizes a raw country selection into what should be persisted:
  the default option (or a blank value) becomes `nil`, anything else is
  passed through unchanged.

  ## Examples

      iex> FullstackWeb.WaitlistLive.Countries.normalize("I don't know yet")
      nil

      iex> FullstackWeb.WaitlistLive.Countries.normalize("")
      nil

      iex> FullstackWeb.WaitlistLive.Countries.normalize(nil)
      nil

      iex> FullstackWeb.WaitlistLive.Countries.normalize("Spain")
      "Spain"

  """
  def normalize(nil), do: nil
  def normalize(""), do: nil
  def normalize(@default), do: nil
  def normalize(country) when is_binary(country), do: country
end
