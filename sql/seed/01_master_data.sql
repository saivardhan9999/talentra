-- =============================================================================
-- Talentra seed :: 01_master_data.sql  (B60: all reference data populated)
-- Real Indian states and cities (with coordinates, in rough population order so the
-- generator can skew towards big cities), industries, job roles, skills with
-- multilingual aliases, qualifications, fields of study and institutions.
-- Lookup tables (enumerations) were already seeded by the schema build.
-- =============================================================================
\set ON_ERROR_STOP on
SET app.current_user_id = '1';
SET synchronous_commit = off;

DO $$
DECLARE v_in bigint := (SELECT id FROM country WHERE iso_alpha2 = 'IN');
BEGIN
    INSERT INTO state (country_id, code, name)
    SELECT v_in, c, n FROM (VALUES
        ('AP','Andhra Pradesh'),('AR','Arunachal Pradesh'),('AS','Assam'),('BR','Bihar'),('CT','Chhattisgarh'),('GA','Goa'),
        ('GJ','Gujarat'),('HR','Haryana'),('HP','Himachal Pradesh'),('JH','Jharkhand'),('KA','Karnataka'),('KL','Kerala'),
        ('MP','Madhya Pradesh'),('MH','Maharashtra'),('MN','Manipur'),('ML','Meghalaya'),('MZ','Mizoram'),('NL','Nagaland'),
        ('OR','Odisha'),('PB','Punjab'),('RJ','Rajasthan'),('SK','Sikkim'),('TN','Tamil Nadu'),('TG','Telangana'),('TR','Tripura'),
        ('UP','Uttar Pradesh'),('UT','Uttarakhand'),('WB','West Bengal'),('AN','Andaman and Nicobar Islands'),('CH','Chandigarh'),
        ('DH','Dadra and Nagar Haveli and Daman and Diu'),('DL','Delhi'),('JK','Jammu and Kashmir'),('LA','Ladakh'),
        ('LD','Lakshadweep'),('PY','Puducherry')) v(c, n)
    ON CONFLICT (country_id, code) DO NOTHING;
END $$;

-- Cities in rough population order (rank = position), so seed.skew() favours the metros.
CREATE TABLE seed.city_src (rank int, name text, state_code text, lat numeric, lon numeric);
INSERT INTO seed.city_src SELECT row_number() OVER (), * FROM (VALUES
 ('Mumbai','MH',19.0760,72.8777),('Delhi','DL',28.6139,77.2090),('Bengaluru','KA',12.9716,77.5946),('Hyderabad','TG',17.3850,78.4867),
 ('Chennai','TN',13.0827,80.2707),('Kolkata','WB',22.5726,88.3639),('Pune','MH',18.5204,73.8567),('Ahmedabad','GJ',23.0225,72.5714),
 ('Jaipur','RJ',26.9124,75.7873),('Surat','GJ',21.1702,72.8311),('Lucknow','UP',26.8467,80.9462),('Kanpur','UP',26.4499,80.3319),
 ('Nagpur','MH',21.1458,79.0882),('Indore','MP',22.7196,75.8577),('Gurugram','HR',28.4595,77.0266),('Noida','UP',28.5355,77.3910),
 ('Thane','MH',19.2183,72.9781),('Bhopal','MP',23.2599,77.4126),('Visakhapatnam','AP',17.6868,83.2185),('Patna','BR',25.5941,85.1376),
 ('Vadodara','GJ',22.3072,73.1812),('Ghaziabad','UP',28.6692,77.4538),('Ludhiana','PB',30.9010,75.8573),('Coimbatore','TN',11.0168,76.9558),
 ('Kochi','KL',9.9312,76.2673),('Agra','UP',27.1767,78.0081),('Nashik','MH',19.9975,73.7898),('Faridabad','HR',28.4089,77.3178),
 ('Madurai','TN',9.9252,78.1198),('Rajkot','GJ',22.3039,70.8022),('Varanasi','UP',25.3176,82.9739),('Thiruvananthapuram','KL',8.5241,76.9366),
 ('Chandigarh','CH',30.7333,76.7794),('Mysuru','KA',12.2958,76.6394),('Bhubaneswar','OR',20.2961,85.8245),('Guwahati','AS',26.1445,91.7362),
 ('Vijayawada','AP',16.5062,80.6480),('Raipur','CT',21.2514,81.6296),('Ranchi','JH',23.3441,85.3096),('Aurangabad','MH',19.8762,75.3433),
 ('Amritsar','PB',31.6340,74.8723),('Prayagraj','UP',25.4358,81.8463),('Howrah','WB',22.5958,88.2636),('Jabalpur','MP',23.1815,79.9864),
 ('Gwalior','MP',26.2183,78.1828),('Jodhpur','RJ',26.2389,73.0243),('Kota','RJ',25.2138,75.8648),('Tiruchirappalli','TN',10.7905,78.7047),
 ('Salem','TN',11.6643,78.1460),('Kozhikode','KL',11.2588,75.7804),('Dehradun','UT',30.3165,78.0322),('Mangaluru','KA',12.9141,74.8560),
 ('Hubballi','KA',15.3647,75.1240),('Tiruppur','TN',11.1085,77.3411),('Warangal','TG',17.9689,79.5941),('Guntur','AP',16.3067,80.4365),
 ('Srinagar','JK',34.0837,74.7973),('Dhanbad','JH',23.7957,86.4304),('Solapur','MH',17.6599,75.9064),('Meerut','UP',28.9845,77.7064),
 ('Vellore','TN',12.9165,79.1325),('Tirunelveli','TN',8.7139,77.7567),('Nellore','AP',14.4426,79.9865),('Tirupati','AP',13.6288,79.4192),
 ('Belagavi','KA',15.8497,74.4977),('Puducherry','PY',11.9416,79.8083),('Jamshedpur','JH',22.8046,86.2029),('Cuttack','OR',20.4625,85.8830),
 ('Hosur','TN',12.7409,77.8253),('Erode','TN',11.3410,77.7172),('Thrissur','KL',10.5276,76.2144),('Kolhapur','MH',16.7050,74.2433),
 ('Udaipur','RJ',24.5854,73.7125),('Ajmer','RJ',26.4499,74.6399),('Gandhinagar','GJ',23.2156,72.6369),('Bhavnagar','GJ',21.7645,72.1519),
 ('Jammu','JK',32.7266,74.8570),('Siliguri','WB',26.7271,88.3953),('Durgapur','WB',23.5204,87.3119),('Bhilai','CT',21.1938,81.3509),
 ('Ujjain','MP',23.1765,75.7885),('Kollam','KL',8.8932,76.6141),('Karimnagar','TG',18.4386,79.1288),('Nizamabad','TG',18.6725,78.0941),
 ('Kurnool','AP',15.8281,78.0373),('Davanagere','KA',14.4644,75.9218),('Gorakhpur','UP',26.7606,83.3732),('Bareilly','UP',28.3670,79.4304),
 ('Aligarh','UP',27.8974,78.0880),('Moradabad','UP',28.8386,78.7733),('Jalandhar','PB',31.3260,75.5762),('Patiala','PB',30.3398,76.3869),
 ('Bikaner','RJ',28.0229,73.3119),('Panaji','GA',15.4909,73.8278),('Shimla','HP',31.1048,77.1734),('Imphal','MN',24.8170,93.9368),
 ('Shillong','ML',25.5788,91.8933),('Agartala','TR',23.8315,91.2868),('Aizawl','MZ',23.7271,92.7176),('Gangtok','SK',27.3389,88.6065),
 ('Kohima','NL',25.6751,94.1086),('Itanagar','AR',27.0844,93.6053),('Port Blair','AN',11.6234,92.7265),('Leh','LA',34.1526,77.5771)
) v(name, state_code, lat, lon);

INSERT INTO city (country_id, state_id, name, latitude, longitude, coordinate_source_id)
SELECT s.country_id, s.id, c.name, c.lat, c.lon, seed.id('coordinate_source', 'mapping_provider')
FROM seed.city_src c JOIN state s ON s.code = c.state_code AND s.country_id = (SELECT id FROM country WHERE iso_alpha2 = 'IN')
ON CONFLICT (country_id, state_id, name) DO NOTHING;
-- rank -> city id (cities that existed before keep their id)
CREATE TABLE seed.city_rank AS
SELECT c.rank, ci.id AS city_id, ci.name FROM seed.city_src c
JOIN state s ON s.code = c.state_code JOIN city ci ON ci.state_id = s.id AND ci.name = c.name;
CREATE UNIQUE INDEX ON seed.city_rank (rank);

INSERT INTO industry (code, name)
SELECT c, n FROM (VALUES ('technology','Technology'),('bfsi','Banking, financial services and insurance'),('manufacturing','Manufacturing'),
    ('healthcare','Healthcare'),('retail','Retail'),('logistics','Logistics and supply chain'),('education','Education'),('construction','Construction'),
    ('real_estate','Real estate'),('hospitality','Hospitality'),('media','Media and entertainment'),('energy','Energy and utilities'),
    ('agriculture','Agriculture'),('government','Government and public sector'),('bpo','BPO and customer services'),('consulting','Consulting'),
    ('fmcg','FMCG')) v(c, n)
ON CONFLICT (code) DO NOTHING;
INSERT INTO industry (code, name, parent_industry_id)
SELECT c, n, (SELECT id FROM industry WHERE code = p) FROM (VALUES
    ('it_services','IT services','technology'),('software_products','Software products','technology'),('telecom','Telecom','technology'),
    ('banking','Banking','bfsi'),('insurance','Insurance','bfsi'),('fintech','Fintech','bfsi'),('automotive','Automotive','manufacturing'),
    ('textiles','Textiles and apparel','manufacturing'),('electronics_mfg','Electronics manufacturing','manufacturing'),
    ('pharma','Pharmaceuticals','healthcare'),('hospitals','Hospitals and clinics','healthcare'),('ecommerce','E-commerce','retail'),
    ('edtech','EdTech','education')) v(c, n, p)
ON CONFLICT (code) DO NOTHING;

INSERT INTO job_role (functional_area_id, code, name)
SELECT seed.id('functional_area', fa), c, n FROM (VALUES
    ('engineering','civil_engineer','Civil Engineer'),('engineering','mechanical_engineer','Mechanical Engineer'),('engineering','electrical_engineer','Electrical Engineer'),
    ('engineering','site_supervisor','Site Supervisor'),('engineering','quality_engineer','Quality Engineer'),
    ('it_software','software_engineer','Software Engineer'),('it_software','java_developer','Java Developer'),('it_software','frontend_developer','Frontend Developer'),
    ('it_software','data_analyst','Data Analyst'),('it_software','data_engineer','Data Engineer'),('it_software','devops_engineer','DevOps Engineer'),
    ('it_software','qa_engineer','QA Engineer'),('it_software','product_manager','Product Manager'),('it_software','ui_ux_designer','UI/UX Designer'),
    ('it_software','mobile_developer','Mobile Developer'),
    ('sales','sales_executive','Sales Executive'),('sales','business_development_manager','Business Development Manager'),
    ('sales','retail_sales_associate','Retail Sales Associate'),('sales','inside_sales','Inside Sales Executive'),('sales','key_account_manager','Key Account Manager'),
    ('operations','operations_executive','Operations Executive'),('operations','store_manager','Store Manager'),('operations','operations_manager','Operations Manager'),
    ('finance','accountant','Accountant'),('finance','financial_analyst','Financial Analyst'),('finance','tax_consultant','Tax Consultant'),
    ('finance','accounts_executive','Accounts Executive'),
    ('human_resources','hr_executive','HR Executive'),('human_resources','recruiter','Recruiter'),('human_resources','talent_acquisition_lead','Talent Acquisition Lead'),
    ('customer_service','customer_support_executive','Customer Support Executive'),('customer_service','telecaller','Telecaller'),
    ('customer_service','voice_process_associate','Voice Process Associate'),
    ('logistics','delivery_executive','Delivery Executive'),('logistics','warehouse_associate','Warehouse Associate'),('logistics','fleet_supervisor','Fleet Supervisor'),
    ('logistics','driver','Driver'),
    ('manufacturing','machine_operator','Machine Operator'),('manufacturing','electrician','Electrician'),('manufacturing','fitter','Fitter'),
    ('manufacturing','welder','Welder'),('manufacturing','production_supervisor','Production Supervisor'),
    ('healthcare','staff_nurse','Staff Nurse'),('healthcare','pharmacist','Pharmacist'),('healthcare','lab_technician','Lab Technician'),
    ('healthcare','medical_representative','Medical Representative')) v(fa, c, n)
ON CONFLICT (code) DO NOTHING;

INSERT INTO skill (skill_category_id, code, name)
SELECT seed.id('skill_category', cat), c, n FROM (VALUES
    ('technical','java','Java'),('technical','spring_boot','Spring Boot'),('technical','python','Python'),('technical','javascript','JavaScript'),
    ('technical','typescript','TypeScript'),('technical','react','React'),('technical','angular','Angular'),('technical','node_js','Node.js'),
    ('technical','sql','SQL'),('technical','postgresql','PostgreSQL'),('technical','mysql','MySQL'),('technical','mongodb','MongoDB'),
    ('technical','aws','AWS'),('technical','azure','Microsoft Azure'),('technical','docker','Docker'),('technical','kubernetes','Kubernetes'),
    ('technical','linux','Linux'),('technical','c_sharp','C#'),('technical','dot_net','.NET'),('technical','php','PHP'),('technical','golang','Go'),
    ('technical','kotlin','Kotlin'),('technical','android','Android'),('technical','ios_swift','iOS (Swift)'),('technical','html_css','HTML and CSS'),
    ('technical','data_analysis','Data analysis'),('technical','machine_learning','Machine learning'),('technical','power_bi','Power BI'),
    ('technical','tableau','Tableau'),('technical','selenium','Selenium'),('technical','manual_testing','Manual testing'),('technical','rest_api','REST APIs'),
    ('technical','microservices','Microservices'),('technical','git','Git'),('technical','autocad','AutoCAD'),('technical','solidworks','SolidWorks'),
    ('technical','plc_programming','PLC programming'),('technical','embedded_c','Embedded C'),('technical','networking','Computer networking'),
    ('functional','accounting','Accounting'),('functional','gst','GST compliance'),('functional','tally','Tally'),('functional','payroll','Payroll'),
    ('functional','recruitment','Recruitment'),('functional','sales','Sales'),('functional','negotiation','Negotiation'),
    ('functional','customer_service','Customer service'),('functional','inventory_management','Inventory management'),
    ('functional','supply_chain','Supply chain'),('functional','digital_marketing','Digital marketing'),('functional','seo','SEO'),
    ('functional','content_writing','Content writing'),('functional','project_management','Project management'),
    ('functional','business_analysis','Business analysis'),('functional','financial_modelling','Financial modelling'),('functional','auditing','Auditing'),
    ('functional','quality_control','Quality control'),('functional','lean_manufacturing','Lean manufacturing'),('functional','retail_operations','Retail operations'),
    ('functional','telecalling','Telecalling'),('functional','field_sales','Field sales'),('functional','lead_generation','Lead generation'),
    ('functional','procurement','Procurement'),
    ('soft','communication','Communication'),('soft','teamwork','Teamwork'),('soft','leadership','Leadership'),('soft','problem_solving','Problem solving'),
    ('soft','time_management','Time management'),
    ('trade','electrical_wiring','Electrical wiring'),('trade','welding','Welding'),('trade','plumbing','Plumbing'),('trade','carpentry','Carpentry'),
    ('trade','driving_lmv','Driving (LMV)'),('trade','driving_hmv','Driving (HMV)'),('trade','two_wheeler_riding','Two-wheeler riding'),
    ('trade','forklift_operation','Forklift operation'),('trade','machine_operation','Machine operation'),('trade','cnc_operation','CNC operation'),
    ('trade','hvac_maintenance','HVAC maintenance'),('trade','masonry','Masonry'),('trade','tailoring','Tailoring'),('trade','nursing_care','Nursing care'),
    ('trade','phlebotomy','Phlebotomy'),
    ('tool','ms_office','MS Office'),('tool','ms_excel','MS Excel'),('tool','sap','SAP'),('tool','salesforce','Salesforce'),('tool','jira','Jira'),
    ('tool','figma','Figma'),('tool','zoho','Zoho')) v(cat, c, n)
ON CONFLICT (code) DO NOTHING;
CREATE TABLE seed.skill_rank AS SELECT row_number() OVER (ORDER BY id) AS rank, id AS skill_id, code FROM skill;
CREATE UNIQUE INDEX ON seed.skill_rank (rank);

-- Aliases: what people actually type, in several languages (search synonyms).
INSERT INTO skill_alias (skill_id, alias_name, language_id)
SELECT (SELECT id FROM skill WHERE code = s), a, (SELECT id FROM language WHERE code = l) FROM (VALUES
    ('java','Core Java','en'),('java','J2EE','en'),('javascript','JS','en'),('react','ReactJS','en'),('postgresql','Postgres','en'),
    ('tally','Tally ERP 9','en'),('ms_excel','Excel','en'),('node_js','NodeJS','en'),('dot_net','ASP.NET','en'),
    ('electrical_wiring','बिजली की वायरिंग','hi'),('electrical_wiring','மின் இணைப்பு வேலை','ta'),('welding','वेल्डिंग','hi'),('welding','வெல்டிங்','ta'),
    ('driving_lmv','LMV licence','en'),('driving_lmv','चार पहिया वाहन चलाना','hi'),('two_wheeler_riding','Bike riding','en'),
    ('two_wheeler_riding','दोपहिया वाहन','hi'),('plumbing','प्लंबिंग','hi'),('tailoring','सिलाई','hi'),('tailoring','தையல்','ta'),
    ('accounting','लेखांकन','hi'),('nursing_care','ನರ್ಸಿಂಗ್ ಆರೈಕೆ','kn'),('telecalling','టెలికాలింగ్','te'),('customer_service','ഉപഭോക്തൃ സേവനം','ml')) v(s, a, l);

INSERT INTO qualification (qualification_level_id, code, name)
SELECT seed.id('qualification_level', lv), c, n FROM (VALUES
    ('below_10th','below_10th','Below 10th'),('class_10','ssc_10th','SSC / 10th'),('class_12','hsc_science','HSC / 12th (Science)'),
    ('class_12','hsc_commerce','HSC / 12th (Commerce)'),('class_12','hsc_arts','HSC / 12th (Arts)'),('iti','iti_electrician','ITI Electrician'),
    ('iti','iti_fitter','ITI Fitter'),('iti','iti_welder','ITI Welder'),('iti','iti_copa','ITI COPA'),('diploma','diploma_mechanical','Diploma in Mechanical Engineering'),
    ('diploma','diploma_civil','Diploma in Civil Engineering'),('diploma','diploma_electrical','Diploma in Electrical Engineering'),
    ('diploma','diploma_computer','Diploma in Computer Engineering'),('graduate','b_tech','B.Tech'),('graduate','b_e','B.E.'),('graduate','b_sc','B.Sc'),
    ('graduate','b_com','B.Com'),('graduate','b_a','B.A.'),('graduate','bca','BCA'),('graduate','bba','BBA'),('graduate','mbbs','MBBS'),
    ('graduate','b_pharm','B.Pharm'),('graduate','bsc_nursing','B.Sc Nursing'),('post_graduate','m_tech','M.Tech'),('post_graduate','mba','MBA'),
    ('post_graduate','mca','MCA'),('post_graduate','m_com','M.Com'),('post_graduate','m_sc','M.Sc'),('post_graduate','m_a','M.A.'),
    ('doctorate','phd','PhD'),('certificate','cert_digital_marketing','Certificate in Digital Marketing'),('certificate','cert_data_science','Certificate in Data Science')) v(lv, c, n)
ON CONFLICT (code) DO NOTHING;

INSERT INTO field_of_study (code, name)
SELECT c, initcap(replace(c, '_', ' ')) FROM unnest(ARRAY['computer_science','information_technology','electronics','electrical','mechanical','civil',
    'commerce','accounting','economics','business_administration','mathematics','physics','chemistry','biology','nursing','pharmacy',
    'english_literature','history','psychology','hotel_management','fashion_design','agriculture','law','medicine','statistics']) c
ON CONFLICT (code) DO NOTHING;

-- Institutions: five kinds in each of the 60 largest cities (AISHE-style reference as natural key).
INSERT INTO institution (name, city_id, country_id, external_ref)
SELECT replace(t, '{c}', r.name), r.city_id, (SELECT id FROM country WHERE iso_alpha2 = 'IN'),
       'AISHE-C-' || lpad((r.rank * 10 + k)::text, 5, '0')
FROM seed.city_rank r
CROSS JOIN LATERAL (SELECT * FROM unnest(ARRAY['{c} Institute of Technology','Government Arts College, {c}','University of {c}',
                    '{c} Polytechnic College','Government ITI, {c}']) WITH ORDINALITY u(t, k)) x
WHERE r.rank <= 60
ON CONFLICT (country_id, external_ref) DO NOTHING;

DO $$
BEGIN
    PERFORM seed.done('master: states', (SELECT count(*) FROM state));
    PERFORM seed.done('master: cities', (SELECT count(*) FROM city));
    PERFORM seed.done('master: industries', (SELECT count(*) FROM industry));
    PERFORM seed.done('master: job roles', (SELECT count(*) FROM job_role));
    PERFORM seed.done('master: skills (+aliases)', (SELECT count(*) FROM skill) + (SELECT count(*) FROM skill_alias));
    PERFORM seed.done('master: qualifications', (SELECT count(*) FROM qualification));
    PERFORM seed.done('master: institutions', (SELECT count(*) FROM institution));
END $$;
