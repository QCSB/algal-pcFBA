% New script for Merging Chl and Cre model
addpath('fasta');
% Load fasta file
if ~exist('fst','var')
    fst = fastaread('Chlamydomonas_reinhardtii_full.txt');
    fst = struct2table(fst);
end

%% Step -1: Load Databases

% bigg database complete
% if ~exist('bigg','var')
%     addpath('/Users/16hy16/Documents/MATLAB/projects/idMapper/BiGG');
%     bigg.mets = readtable('bigg_models_metabolites_complete.txt');
% end

% load chlamycyc id
if ~exist('chlamycyc','var')
    % read raw data compounds, enzrxns, genes, protcplxs, rxns, and
    % metabolicRxns sbml
    pth = 'chlamycyc/9.0/data';
    addpath(pth);
    
    chlamycyc.compounds_raw = readcell([pth,'/compounds.dat'],'Delimiter',' - ');
    chlamycyc.compounds_raw(find(startsWith(chlamycyc.compounds_raw(:,1),'#')),:) = [];
    chlamycyc.compounds_raw = chlamycyc.compounds_raw(:,1:2);
    
    chlamycyc.enzrxns_raw = readcell([pth,'/enzrxns.dat'],'Delimiter',' - ');
    chlamycyc.enzrxns_raw(find(startsWith(chlamycyc.enzrxns_raw(:,1),'#')),:) = [];
    chlamycyc.enzrxns_raw = chlamycyc.enzrxns_raw(:,1:2);
    chlamycyc.enzrxns_raw2 = readcell('enzymes.col','FileType','text','Delimiter','\t');
    chlamycyc.enzrxns_raw2 = chlamycyc.enzrxns_raw2(25:end,1:3);
    
    chlamycyc.genes_raw = readcell([pth,'/genes.dat'],'Delimiter',' - ');
    chlamycyc.genes_raw(find(startsWith(chlamycyc.genes_raw(:,1),'#')),:) = [];
    chlamycyc.genes_raw = chlamycyc.genes_raw(:,1:2);
    
    chlamycyc.protcplxs_raw = readcell([pth,'/protcplxs.col'],'FileType','text','Delimiter','\t');
    chlamycyc.protcplxs_raw(find(startsWith(chlamycyc.protcplxs_raw(:,1),'#')),:) = [];
    
    chlamycyc.rxns_raw = readcell([pth,'/reactions.dat'],'Delimiter',' - ');
    chlamycyc.rxns_raw(find(startsWith(chlamycyc.rxns_raw(:,1),'#')),:) = [];
    chlamycyc.rxns_raw = chlamycyc.rxns_raw(:,1:2);
    
    chlamycyc.metabolicRxns = sbmlimport('metabolic-reactions.xml');
    % parse out metabolic Reaction names
    chlamycyc.metabolicRxnNames = cell(length(chlamycyc.metabolicRxns.Reactions),1);
    for i = 1:length(chlamycyc.metabolicRxnNames)
        chlamycyc.metabolicRxnNames{i} = chlamycyc.metabolicRxns.Reactions(i).Name;
    end
    
    % Process .dat file info
    chlamycyc.compounds = datParse(chlamycyc.compounds_raw,{'UNIQUE-ID','COMMON-NAME','INCHI','INCHI-KEY'});
    chlamycyc.genes = datParse(chlamycyc.genes_raw,{'UNIQUE-ID','TYPES','COMMON-NAME','PRODUCT'});
    chlamycyc.genes(end,:) = [];
    chlamycyc.rxns = datParse(chlamycyc.rxns_raw,{'UNIQUE-ID','ENZYMATIC-REACTION','LEFT','RIGHT'});
    chlamycyc.enzrxns = datParse(chlamycyc.enzrxns_raw,{'UNIQUE-ID','COMMON-NAME','ENZYME','REACTION'});
    
    % add reaction stoichiometry to hmcyc.rxns
    % first put everything to default: -1 for reagents, +1 for products
    chlamycyc.rxns(:,5:6) = cell(length(chlamycyc.rxns),2);
    for i = 1:length(chlamycyc.rxns)
        if ~isempty(chlamycyc.rxns{i,3})
            chlamycyc.rxns{i,5} = -1*ones(1,length(split(chlamycyc.rxns{i,3},',')));
        end
        if ~isempty(chlamycyc.rxns{i,4})
            chlamycyc.rxns{i,6} = ones(1,length(split(chlamycyc.rxns{i,4},',')));
        end
    end
    
    % search for coef other than 1 in rxns_raw
    rxnIdx = 1;
    for i = 1:length(chlamycyc.rxns_raw)
        if strcmp(chlamycyc.rxns_raw{i,1},'//')
            rxnIdx = rxnIdx + 1;
    
        elseif strcmp(chlamycyc.rxns_raw{i,1},'^COEFFICIENT')
            if strcmp(chlamycyc.rxns_raw{i-1,1},'LEFT')
                idx = find(strcmp(split(chlamycyc.rxns{rxnIdx,3},','),chlamycyc.rxns_raw{i-1,2}));
                try
                    chlamycyc.rxns{rxnIdx,5}(idx) = -chlamycyc.rxns_raw{i,2};
                catch
                    warning('Unknown stoich assignment error: line %d, rxn %d\n',i,rxnIdx);
                end
            elseif strcmp(chlamycyc.rxns_raw{i-1,1},'RIGHT')
                idx = find(strcmp(split(chlamycyc.rxns{rxnIdx,4},','),chlamycyc.rxns_raw{i-1,2}));
                try
                    chlamycyc.rxns{rxnIdx,6}(idx) = chlamycyc.rxns_raw{i,2};
                catch
                    warning('Unknown stoich assignment error: line %d, rxn %d\n',i,rxnIdx);
                end
            end
        end
    end
    
    % add reaction formula from biocyc.metabolicRxns to biocyc.rxns 7th col
    chlamycyc.rxns(:,7) = cell(length(chlamycyc.rxns),1);
    
    for i = 1:length(chlamycyc.rxns)
        chlamycyc.rxns{i,7} = '';
        if isempty(chlamycyc.rxns{i,1})
            continue;
        end
    
        idx = find(strcmp(chlamycyc.metabolicRxnNames,chlamycyc.rxns{i,1}));
        if isempty(idx)
            idx = find(startsWith(chlamycyc.metabolicRxnNames,chlamycyc.rxns{i,1}));
        end
    
        if isempty(idx)
            continue;
        end
    
        chlamycyc.rxns{i,7} = char(chlamycyc.metabolicRxns.Reactions(idx(1),1).Reaction);
    end
    
    % Constructing humancyc 'S matrix'
    chlamycyc.S = zeros(length(chlamycyc.compounds),length(chlamycyc.rxns));
    for i = 1:length(chlamycyc.rxns)
    
        if ~isempty(chlamycyc.rxns{i,3})
    %       find reagents from hm.rxns
            reag = split(chlamycyc.rxns{i,3},',');
    %       assign to hmcyc.S
            for j = 1:length(reag)
                idx = find(strcmp(chlamycyc.compounds(:,1),reag{j}));
                chlamycyc.S(idx,i) = chlamycyc.rxns{i,5}(j);
            end
        end
    
    %   same for products
        if ~isempty(chlamycyc.rxns{i,4})
            prod = split(chlamycyc.rxns{i,4},',');
            for j = 1:length(prod)
                idx = find(strcmp(chlamycyc.compounds(:,1),prod{j}));
                chlamycyc.S(idx,i) = chlamycyc.rxns{i,6}(j);
            end
        end
    end
    
    % Process hmcyc.protcplxs and constructing hmcyc.P matrix, relationship
    % between genes and cplx
    [~,w] = size(chlamycyc.protcplxs_raw);
    
    chlamycyc.protcplxs = [chlamycyc.protcplxs_raw(2:end,1),chlamycyc.protcplxs_raw(2:end,w),chlamycyc.protcplxs_raw(2:end,2)];
    chlamycyc.P = zeros(length(chlamycyc.genes),length(chlamycyc.protcplxs));
    
    for i = 1:length(chlamycyc.protcplxs)
    
        if isempty(chlamycyc.protcplxs{i,2}) || any(ismissing(chlamycyc.protcplxs{i,2}))
            continue;
        end
    
    %   analysing complex stoich from string
        su = split(chlamycyc.protcplxs{i,2},',');
        for j = 1:length(su)
            dt = split(su{j},'*');
            idx = find(strcmp(chlamycyc.genes(:,4),dt{2}));
            if isempty(idx)
                idx = find(contains(chlamycyc.genes(:,4),dt{2}));
            end

            if isempty(idx)
                warning('Unrecognized protein: %s',dt{2});
                continue;

            elseif length(idx) ~= 1
                warning('Duplication in protein: row %d and row %d',idx(1),idx(2));
                chlamycyc.P(idx(1),i) = str2double(dt{1});

            else
                chlamycyc.P(idx,i) = str2double(dt{1});
            end
        end
    end
    
    % Constructing hmcyc.C matrix, relationship between genes and enzrxns
    chlamycyc.C = zeros(length(chlamycyc.genes),length(chlamycyc.enzrxns));
    
    for i = 1:length(chlamycyc.enzrxns)
        if isempty(chlamycyc.enzrxns{i,3})
            continue;
        end
    
    %   if enzrxn col 3 is directly found as a gene, record and continue
    %   elseif find it as a complex, copy the column from hmcyc.P
    %   else return error
        idx = find(strcmp(chlamycyc.genes(:,4),chlamycyc.enzrxns{i,3}));
        if isempty(idx)
            idx = find(contains(chlamycyc.genes(1:end-1,4),chlamycyc.enzrxns{i,3}));
        end
        
        if ~isempty(idx)
            if length(idx) ~= 1
                warning('Duplication in genes: row %d and row %d',idx(1),idx(2));
            end
            chlamycyc.C(idx(1),i) = 1;
        else
            idx = find(strcmp(chlamycyc.protcplxs(:,1),chlamycyc.enzrxns{i,3}));
            if isempty(idx)
                warning('Unrecognized protein or protcplx: %s',chlamycyc.enzrxns{i,3});
                continue;
            end
    
            chlamycyc.C(:,i) = chlamycyc.P(:,idx);
        end
    end
    
    % Constructing hmcyc.K matrix, relationship between enzrxns and rxns
    chlamycyc.K = zeros(length(chlamycyc.rxns),length(chlamycyc.enzrxns));
    
    for i = 1:length(chlamycyc.enzrxns)
        if isempty(chlamycyc.enzrxns{i,4})
            continue;
        end
        idx = find(strcmp(chlamycyc.rxns(:,1),chlamycyc.enzrxns{i,4}));
        if isempty(idx)
            warning('Unrecognized rxns mapping from enzrxns: %s',chlamycyc.enzrxns{i,4});
        end
    
        chlamycyc.K(idx,i) = 1;
    end

%   add reaction formula to enzrxns
    chlamycyc.enzrxns(:,5) = cell(length(chlamycyc.enzrxns),1);

    for i = 1:length(chlamycyc.enzrxns)
        chlamycyc.enzrxns{i,5} = '';
        idx = find(strcmp(chlamycyc.enzrxns_raw2(:,1),chlamycyc.enzrxns{i,1}));
        if isempty(idx)
            continue;
        end

        for j = 1:length(idx)
            chlamycyc.enzrxns{i,5} = [chlamycyc.enzrxns{i,5},chlamycyc.enzrxns_raw2{idx(j),3}];
            if j ~= length(idx)
                chlamycyc.enzrxns{i,5} = [chlamycyc.enzrxns{i,5},','];
            end
        end
    end

%   add change chloroplast geneName to locus_tag
    for i = 1:length(chlamycyc.genes)
        if startsWith(chlamycyc.genes{i,3},'Cre')
            continue;
        end

        idx = find(contains(fst.Header,['[gene=',chlamycyc.genes{i,3},']'],'IgnoreCase',true));
        if ~isempty(idx)
            if i == 2761
                lt = split(fst.Header{idx(2)},'[');
            else
                lt = split(fst.Header{idx},'[');
            end
            chlamycyc.genes{i,3} = lt{1};
        end
    end
end
clear prod reag rxnIdx idx i j su w pth dt lt;

%% Step 0: Load and Modify Both Models

% chloroplast model
if ~exist('model_chl_ori','var')
    model_chl_ori = readCbModel('iGRMModel_metmod_biomod_formadded_bmcons1_v1.xml');
    model_chl_ori = changeObjective(model_chl_ori,'BIOMASS_at_Chl_bio');
    model_chl_ori = removeGenesFromModel(model_chl_ori,'CHLREDRAFT_108283');
    model_chl_pc = pcModel(model_chl_ori,'Chlamydomonas_reinhardtii_full.txt',150);
%   genes not found in NCBI: CHLREDRAFT_108283 and CHLREDRAFT_119728
%       remove CHLREDRAFT_108283...
%   gene CHLREDRAFT_119728 plays an extremely important role...
end

% C. reinhardtii full model
if ~exist('model_cre','var')
    model_cre_ori = readCbModel('iCre1355_auto.xml');
    model_cre = model_cre_ori;

    ln = model_cre.rules{1438};
    ln(1) = [];
    ln(length(ln)) = [];
    model_cre.rules{1438} = ln;
    model_cre = changeObjective(model_cre,'Biomass_Chlamy_auto');

%   Remove gene PSBW (https://pmn.plantcyc.org/CHLAMY/NEW-IMAGE?type=REACTION&object=RXN-8378)
    model_cre.rules{1437} = '';
    model_cre = removeGenesFromModel(model_cre,'PSBW');

%   Change rules format (remove the attached '.t1.1')
    geneList = model_cre.genes;

    for i = 1:length(geneList)
        if startsWith(geneList{i},'Cre')
            gn = geneList{i};
            gn(end-4:end) = [];
            geneList{i} = gn;
        end
    end

%   Highly suspecting that duplicate genes are almost identical
%   remove all of the duplicates
    uniqueGene = {};
    rm = [];

    for i = 1:length(geneList)
        if ~any(strcmp(uniqueGene,geneList{i}))
            uniqueGene{end+1,1} = geneList{i};
        else
            rm(end+1,1) = i;
        end
    end

%   Remove duplicate genes and change gene format
    model_cre = removeGenesFromModel(model_cre,model_cre.genes(rm));

    for i = 1:length(model_cre.genes)
        if startsWith(model_cre.genes{i},'Cre')
            gn = model_cre.genes{i};
            gn(end-4:end) = [];
            model_cre.genes{i} = gn;
        end
    end
    clear rm ln geneList uniqueGene gn i;

%   mapping rxns using genes
    model_cre.rxnMetaCycID = cell(length(model_cre.rxns),1);
    model_cre.rxnMetaCycIDCand = cell(length(model_cre.rxns),1);
%{
%   add InChI, InChIKey, and biocyc ID to mets, MetaNetX ID to rxns
    model_cre.metBioCycID = cell(length(model_cre.mets),1);
    model_cre.metInChIKey = cell(length(model_cre.mets),1);
    model_cre.metInChI = cell(length(model_cre.mets),1);
    model_cre.metMetaNetXID = cell(length(model_cre.mets),1);

    for i = 1:length(model_cre.mets)
        model_cre.metBioCycID{i} = '';
        model_cre.metInChIKey{i} = '';

        met = split(model_cre.mets{i},'[');
        met = met{1};

        idx = find(strcmp(bigg.mets.universal_bigg_id,met));

        for j = 1:length(idx)

%           biocyc
            if ~isempty(bigg.mets.bigg_id{idx(j)}) && isempty(model_cre.metBioCycID{i})
                model_cre.metBioCycID{i} = bigg.mets.biocyc_id{idx(j)};
            elseif ~isempty(bigg.mets.bigg_id{idx(j)}) && ~isempty(model_cre.metBioCycID{i})
                if ~strcmp(bigg.mets.bigg_id{idx(j)},model_cre.metBioCycID{i})
                    warning('Self contradiction %d\n',i);
                end
            end
            
%           inchi
            if ~isempty(bigg.mets.inchi{idx(j)}) && isempty(model_cre.metInChI{i})
                model_cre.metInChI{i} = bigg.mets.inchi{idx(j)};
            elseif ~isempty(bigg.mets.inchi{idx(j)}) && ~isempty(model_cre.metInChI{i})
                if ~strcmp(bigg.mets.inchi{idx(j)},model_cre.metInChI{i})
                    warning('Self contradiction %d\n',i);
                end
            end

%           inchikey
            if ~isempty(bigg.mets.inchikey{idx(j)}) && isempty(model_cre.metInChIKey{i})
                model_cre.metInChIKey{i} = bigg.mets.inchikey{idx(j)};
            elseif ~isempty(bigg.mets.inchikey{idx(j)}) && ~isempty(model_cre.metInChIKey{i})
                if ~strcmp(bigg.mets.inchikey{idx(j)},model_cre.metInChIKey{i})
                    warning('Self contradiction %d\n',i);
                end
            end

%           MetaNetX
            if ~isempty(bigg.mets.metanetx_id{idx(j)}) && isempty(model_cre.metMetaNetXID{i})
                model_cre.metMetaNetXID{i} = bigg.mets.metanetx_id{idx(j)};
            elseif ~isempty(bigg.mets.metanetx_id{idx(j)}) && ~isempty(model_cre.metMetaNetXID{i})
                if ~strcmp(bigg.mets.metanetx_id{idx(j)},model_cre.metMetaNetXID{i})
                    warning('Self contradiction %d\n',i);
                end
            end
        end
    end
    clear ln gn rm uniqueGene geneList met idx i j;

%   Mapping metabolites to chlamycyc id...which is similar to biocyc id
    model_cre.metChlamyCycID = cell(length(model_cre.mets),1);
    model_cre.metChlamyCycIDCand = cell(length(model_cre.mets),1);

    for i = 1:length(model_cre.metChlamyCycID)

%       list out candidates and scores
        cand = [];

%       first collect all candidates
%       using biocyc
        if ~isempty(model_cre.metBioCycID{i})
            idx = find(strcmp(chlamycyc.compounds(:,1),model_cre.metBioCycID{i}));
            if ~isempty(idx)
                cand(end+1,1) = idx;
            end
        end

%       using inchi
        if ~isempty(model_cre.metInChI{i})
            idx = find(strcmp(chlamycyc.compounds(:,3),model_cre.metInChI{i}));
            for j = 1:length(idx)
                cand(end+1,1) = idx(j);
            end
        end

%       using inchikey
        if ~isempty(model_cre.metInChIKey{i})
            idx = find(strcmp(chlamycyc.compounds(:,4),model_cre.metInChIKey{i}));
            for j = 1:length(idx)
                cand(end+1,1) = idx(j);
            end
        end

%       continue if no candidate is available
        if isempty(cand)
            continue;
        end

%       scoring for each candidates...
        cand = unique(cand);
        sc = zeros(length(cand),1);

        for j = 1:length(cand)
            if ~isempty(model_cre.metBioCycID{i}) && ~isempty(chlamycyc.compounds{cand(j),1})
                if strcmp(model_cre.metBioCycID{i},chlamycyc.compounds{cand(j),1})
                    sc(j) = sc(j) + 1;
                end
            end

            if ~isempty(model_cre.metInChI{i}) && ~isempty(chlamycyc.compounds{cand(j),3})
                if strcmp(model_cre.metInChI{i},chlamycyc.compounds{cand(j),3})
                    sc(j) = sc(j) + 1;
                end
            end

            if ~isempty(model_cre.metInChIKey{i}) && ~isempty(chlamycyc.compounds{cand(j),4})
                if strcmp(model_cre.metInChIKey{i},chlamycyc.compounds{cand(j),4})
                    sc(j) = sc(j) + 1;
                end
            end
        end

%       safeguard
        if any(sc == 0)
            error('something goes wrong');
        end

%       choose the highest scoring cand
        [~,idx] = max(sc);
        model_cre.metChlamyCycID{i} = chlamycyc.compounds{cand(idx),1};
        model_cre.metChlamyCycIDCand{i} = chlamycyc.compounds(cand,1);
    end

%   Map reactions using metabolites
    model_cre.rxnChlamyCycID = cell(length(model_cre.rxns),1);
    model_cre.rxnChlamyCycIDCand = cell(length(model_cre.rxns),1);

    for i = 1:length(model_cre.rxnChlamyCycID)

%       construct a chlamycyc.S column from model_cre.S and available
%       metabolite mappings
        col = zeros(length(chlamycyc.compounds),1);
        reac = find(model_cre.S(:,i)<0);
        prod = find(model_cre.S(:,i)>0);

        for j = 1:length(reac)
            if ~isempty(model_cre.metChlamyCycID{reac(j)})
                col(find(strcmp(chlamycyc.compounds(:,1),model_cre.metChlamyCycID{reac(j)}))) = -1;
            end
        end
        for j = 1:length(prod)
            if ~isempty(model_cre.metChlamyCycID{prod(j)})
                col(find(strcmp(chlamycyc.compounds(:,1),model_cre.metChlamyCycID{prod(j)}))) = 1;
            end
        end

%       if col contains too little nonzero, continue
        if length(find(col)) < 2
            continue;
        end

%       compare to chlamycyc.S
        sc = col'*chlamycyc.S;
        fl = length(reac)+length(prod);

        if ~any(sc>(0.75*fl))
            continue;
        end

        [~,idx] = max(sc);
        model_cre.rxnChlamyCycID{i} = chlamycyc.rxns{idx,1};
    end
%}

%   add model_cre.reactions
    model_cre.reactions = cell(length(model_cre.rxns),1);
    for i = 1:length(model_cre.reactions)
        model_cre.reactions(i) = printRxnFormula(model_cre,...
            'rxnAbbrList',model_cre.rxns{i},'printFlag',false);
    end
end

% call pcModel constructor
if ~exist('model_cre_pc','var')
    model_cre_pc = pcModel(model_cre,'Chlamydomonas_reinhardtii_full.txt',150);
end

% Change solver to gurobi
changeCobraSolver('gurobi','all',0);

% =========================================================================
%% Step 1: Remove reactions purely in chloroplast, eyespot, thylakoid, or
% only between them
% =========================================================================
model_cyt = model_cre;
plastidRxn = {};

for i = 1:length(model_cyt.rxns)
    metList = model_cyt.mets(find(model_cyt.S(:,i)));
    
    for j = 1:length(metList)
%       Break if any mets is found not within any of the 3 compartment
        if (~contains(metList{j},'[h]') && ~contains(metList{j},'[u]') && ~contains(metList{j},'[s]'))
            break;
        end
        
%       If reaches the end of metList without triggering break, add the rxn
%       to remove list
        if j == length(metList)
            plastidRxn{1,length(plastidRxn)+1} = model_cyt.rxns{i};
        end
    end
end

model_cyt = removeRxns(model_cyt,plastidRxn);
clear metList;

% Collect a structure for gap filling
% gpStruct.rxns = removedRxn;
% gpStruct.mets = model_cre_ori.mets;
% gpStruct.U = model_cre_ori.S;
% gpStruct.lb = model_cre_ori.lb;
% gpStruct.ub = model_cre_ori.ub;
% 
% r = [];
% for i = 1:length(model_cre_ori.rxns)
%     if ~any(strcmp(removedRxn,model_cre_ori.rxns{i}))
%         r(length(r)+1,1) = i;
%     end
% end
% gpStruct.U(:,r) = [];
% gpStruct.lb(r) = [];
% gpStruct.ub(r) = [];
% 
% r = [];
% for i = 1:length(gpStruct.mets)
%     if ~any(gpStruct.U(i,:))
%         r(length(r)+1,1) = i;
%     end
% end
% gpStruct.U(r,:) = [];
% gpStruct.mets(r) = [];

clear r;

% =========================================================================
%% Step 2: Find 'transported' mets
% =========================================================================
%   'transport' here defined as any rxn that contains mets both within and
%   outside of chl-eye-thy
%   'transported mets' is defined as the mets inside chl-eye-thy

% Current approach:
%   disregard all tr_mets that are only there due be being a part of the
%   biomass rxn
%   remove those mets from biomass rxn
%   sync chl and cyt biomass rate in the end

tr_rxns_cyt = {};
tr_mets_cyt = {};

for i = 1:length(model_cyt.rxns)
    metList = model_cyt.mets(find(model_cyt.S(:,i)));
    
%   Exclude biomass related
    if contains(model_cyt.rxns{i},'Biomass_')
        continue;
    end
    
%   Now no rxns are purely within chl-eye-thy. So if any met of a rxn is
%   found to contain chl-eye-thy mets, thats a 'transport rxn'
    if (any(contains(metList,'[h]')) || any(contains(metList,'[u]')) || any(contains(metList,'[s]')))
        tr_rxns_cyt{length(tr_rxns_cyt)+1,1} = model_cyt.rxns{i};
        
%       Adding transported mets
        for j = 1:length(metList)
            if ((contains(metList{j},'[h]') || contains(metList{j},'[u]') || contains(metList{j},'[s]')) && (~any(strcmp(tr_mets_cyt,metList{j}))))
                tr_mets_cyt{length(tr_mets_cyt)+1,1} = metList{j};
            end
        end
    end
end

% Matching Cre mets to Chl
%   If met not found, 0
%   If met is found but no EX_, -1
%   If EX_ if found, ex rxn #
tr_mets_map = [0,0,0,0,0,0,0,0,-1,-1,-1,-1,0,492,756,493,494,0,-1,495,496,498,-1,489,500,...
    491,501,757,0,502,503,504,506,505,514,516,517,518,0,0,509,510,511,779,512,519,...
    520,-1,758,523,759,-1,524,525,602,0,528,-1,556,530,532,-1,533,736,-1,-1,...
    738,780,-1,-1,534,535,537,539,540,541,543,544,-1,744,639,0,-1,546,0,547,...
    548,-1,549,0,0,0,0,-1,746,748,750,551,0,553,552,752,761,-1,0,-1,742,0,...
    760,762,0,0,-1,497,499,507,594,0,521,-1,522,526,527,531,-1,536,538,545,-1,-1];
tr_mets_map = tr_mets_map';

% CURRENT PROBLEM:
%   1. glyc exchange has grRules in model_cre, but glyc doesn't exist in
%   model_chl as a met
%   2. so does methf[c]
%   3. so does ptrc[c]

% Prepare an exchange reaction for tr_mets_map entries of 0 and -1
%   (if it does not have an direct exchange already)
for i = 1:length(tr_mets_map)
    if ((tr_mets_map(i) == 0) || (tr_mets_map(i) == -1))
        metId = find(strcmp(model_cyt.mets,tr_mets_cyt{i}));
        
%       Checking if an exchange already exists
        exBool = false;
        rxnIdList = find(model_cyt.S(metId,:));
        for j = 1:length(rxnIdList)
            if length(find(model_cyt.S(:,rxnIdList(j)))) == 1
                exBool = true;
            end
        end
                
%       Only add if exBool is false
%       Also only excretion is allowed
        if exBool == false
            model_cyt = addExchangeRxn(model_cyt,tr_mets_cyt{i},0,1000);
        end
    end
end

% Remove any biomass precursors that are in chl-eye-thy compartments
idx = find(strcmp(model_cyt.rxns,'Biomass_Chlamy_auto'));

for i = 1:length(model_cyt.mets)
    if model_cyt.S(i,idx) ~= 0
        if (contains(model_cyt.mets{i},'[h]') || contains(model_cyt.mets{i},'[u]') || contains(model_cyt.mets{i},'[s]'))
            model_cyt.S(i,idx) = 0;
        end
    end
end

% Allow g3p <->13dgp <-> 3pg in cytosol
% suggested by EC.00318-12
model_cyt = changeRxnBounds(model_cyt,{'GAPDH_nadp','GAPDHi'},[-1000,-1000],'l');

clear metId rxnIdList exBool idx gn;

% =========================================================================
%% Step 3: Prepare chl model
% =========================================================================

model_chl_only = model_chl_ori;

% Adding some exchange reactions
%   this is done in conjuction to step 2
model_chl_only = addExchangeRxn(model_chl_only,'3pg[c]',-1000,1000);
model_chl_only = addExchangeRxn(model_chl_only,'ala__b[c]',-1000,1000);
model_chl_only = addExchangeRxn(model_chl_only,'g1p[c]',-1000,1000);
model_chl_only = addExchangeRxn(model_chl_only,'g6p[c]',-1000,1000);
model_chl_only = addExchangeRxn(model_chl_only,'h2o2[c]',-1000,1000);

model_chl_only = addExchangeRxn(model_chl_only,'gluth[c]',-1000,1000);
model_chl_only = addExchangeRxn(model_chl_only,'gtp[c]',-1000,1000);

% add glycerol 3-P transport
model_chl_only = addReaction(model_chl_only,'Tr_glyl3pth_c',...
    'metaboliteList',{'glyl3p[c]','glyl3p[e]'},...
    'stoichCoeffList',[-1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);

model_chl_only = changeRxnBounds(model_chl_only,'NanoG0511',0,'l');

% add transport for free fatty acids: C160, C180, C181(9Z)
model_chl_only = addReaction(model_chl_only,'Tr_c160th_c',...
    'metaboliteList',{'c160[c]','c160[e]'},...
    'stoichCoeffList',[-1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);

model_chl_only = addReaction(model_chl_only,'Tr_c180th_c',...
    'metaboliteList',{'c180[c]','c180[e]'},...
    'stoichCoeffList',[-1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);

model_chl_only = addReaction(model_chl_only,'Tr_c181th_c',...
    'metaboliteList',{'c181[c]','c181[e]'},...
    'stoichCoeffList',[-1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);

% Add metabolic pathway to FAs

% adding C18:1(11Z)
model_chl_only = addReaction(model_chl_only,'3OAS181',...
    'metaboliteList',{'h[c]','malcoa[c]','c161acp[c]','co2[c]','coa[c]','3ocvac11eACP[c]'},...
    'stoichCoeffList',[-1,-1,-1,1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'3OAR181',...
    'metaboliteList',{'3ocvac11eACP[c]','nadph[c]','3hcvac11eACP[c]','nadp[c]'},...
    'stoichCoeffList',[-1,-1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'3HAD181',...
    'metaboliteList',{'3hcvac11eACP[c]','h2o[c]','t3c11vaceACP[c]'},...
    'stoichCoeffList',[-1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'EAR181x',...
    'metaboliteList',{'h[c]','nadh[c]','t3c11vaceACP[c]','nad[c]','c181(7)acp[c]'},...
    'stoichCoeffList',[-1,-1,-1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'EAR181y',...
    'metaboliteList',{'h[c]','nadph[c]','t3c11vaceACP[c]','nadp[c]','c181(7)acp[c]'},...
    'stoichCoeffList',[-1,-1,-1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'FA181ACPHi',...
    'metaboliteList',{'h2o[c]','c181(7)acp[c]','h[c]','acp[c]','c181(7)[c]'},...
    'stoichCoeffList',[-1,-1,1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);

% C18:2(9Z,12Z)
model_chl_only = addReaction(model_chl_only,'ACP1829Z12ZD12DS_h',...
    'metaboliteList',{'h[c]','fdxr[c]','o2[c]','c181acp[c]','fdxo[c]','h2o[c]','c182acp[c]'},...
    'stoichCoeffList',[-2,-1,-1,-1,1,2,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'FA182ACPHi',...
    'metaboliteList',{'h2o[c]','c182acp[c]','h[c]','acp[c]','c182[c]'},...
    'stoichCoeffList',[-1,-1,1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'FACOAL182',...
    'metaboliteList',{'coa[c]','c182[c]','h2o[c]','c182coa[c]'},...
    'stoichCoeffList',[-1,-1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);

% C18:3(9Z,12Z,15Z)
model_chl_only = addReaction(model_chl_only,'ACP1839Z1215ZD15DS_h',...
    'metaboliteList',{'h[c]','fdxr[c]','o2[c]','c182acp[c]','fdxo[c]','h2o[c]','c183(3)acp[c]'},...
    'stoichCoeffList',[-2,-1,-1,-1,1,2,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'FA183ACPHi',...
    'metaboliteList',{'h2o[c]','c183(3)acp[c]','h[c]','acp[c]','c183(3)[c]'},...
    'stoichCoeffList',[-1,-1,1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);
model_chl_only = addReaction(model_chl_only,'FACOAL183',...
    'metaboliteList',{'coa[c]','c183(3)[c]','h2o[c]','c183(3)coa[c]'},...
    'stoichCoeffList',[-1,-1,1,1],...
    'lowerBound',0,...
    'upperBound',1000);

model_chl_only = addExchangeRxn(model_chl_only,'c181(7)[c]',-1000,1000);
model_chl_only = addExchangeRxn(model_chl_only,'c182[c]',-1000,1000);

% change biomass precursors
%   mgdg
model_chl_only.S(344,691) = 0;
model_chl_only.S(347,691) = 0;
model_chl_only.S(691,691) = 0;
%   dgdg
model_chl_only.S(346,692) = 0;
model_chl_only.S(349,692) = 0;
model_chl_only.S(692,692) = 0;
%   sqdg
model_chl_only.S(371,693) = 0;
model_chl_only.S(372,693) = 0;
model_chl_only.S(693,693) = 0;

% Adding chl genes to cre
geneMap = zeros(length(model_chl_only.genes),1);

for i = 1:length(model_chl_only.genes)
    
%   First try to find chl gene from cre genes
    idx = find(strcmp(model_cyt.genes,model_chl_only.genes{i}));
    
    if ~isempty(idx)
        geneMap(i) = idx;
        continue;
    end
        
%   If not found, locate it in fasta
    idx = find(contains(fst.Header,[model_chl_only.genes{i},']']));
    
%   If doesn't appear in fasta, add the chl gene with a warning
    if isempty(idx)
        warning('Adding chl gene to merged model %s',model_chl_only.genes{i});
        model_cyt.genes{end+1,1} = model_chl_ori.genes{i};
        geneMap(i) = length(model_cyt.genes);
        continue;
    end
        
%   If is found in fasta, convert to Cre format and find again
    gn = split(fst.Header(idx),'[');
    gn = gn{1};
    idx = find(startsWith(model_cyt.genes,gn));

    if isempty(idx)
        warning('adding chl gene to merged model %s',gn);
        model_cyt.genes{end+1,1} = gn;
        geneMap(i) = length(model_cyt.genes);
    elseif length(idx) == 1
        geneMap(i) = idx;
    else
        error('more than 1 match');
    end
end

% Editing gene rules of chl model to match geneMap
newRules = cell(length(model_chl_only.rules),1);
baseLen = length(model_cre_ori.genes);

for i = 1:length(model_chl_only.rules)
    oldRule = model_chl_only.rules{i};
    [startIdx,endIdx] = regexp(oldRule,'(\d+)');
    
%   Continue if no number is found
    if isempty(startIdx)
        newRules{i} = oldRule;
        continue;
    end
    
%   If found then start parsing using geneMap
    newRules{i} = oldRule(1:(startIdx(1)-1));
    for j = 1:length(startIdx)
        
        newNo = geneMap(str2num(oldRule(startIdx(j):endIdx(j))));
        newRules{i} = [newRules{i},int2str(newNo)];
        
        if j ~= length(startIdx)
            newRules{i} = [newRules{i},oldRule(endIdx(j)+1:startIdx(j+1)-1)];
        else
            newRules{i} = [newRules{i},oldRule(endIdx(j)+1:length(oldRule))];
        end
    end
end

clear oldRule startIdx endIdx newNo;

% To distinguish mets between cyt and chl model:
%   change [e] to [E]
%   change [h] to [H]
%   change [u] to [U]
%   change [s] to [S]

for i = 1:length(model_chl_only.mets)
    
%   Changing compartment to upper case
    if contains(model_chl_only.mets{i},'[e]')
        model_chl_only.mets{i} = erase(model_chl_only.mets{i},'[e]');
        model_chl_only.mets{i} = [model_chl_only.mets{i},'[E]'];
        
    elseif contains(model_chl_only.mets{i},'[c]')
        model_chl_only.mets{i} = erase(model_chl_only.mets{i},'[c]');
        model_chl_only.mets{i} = [model_chl_only.mets{i},'[H]'];
        
    elseif contains(model_chl_only.mets{i},'[u]')
        model_chl_only.mets{i} = erase(model_chl_only.mets{i},'[u]');
        model_chl_only.mets{i} = [model_chl_only.mets{i},'[U]'];
        
    elseif contains(model_chl_only.mets{i},'[s]')
        model_chl_only.mets{i} = erase(model_chl_only.mets{i},'[s]');
        model_chl_only.mets{i} = [model_chl_only.mets{i},'[S]'];
        
    else
        error('Unrecognized compartment: %d\n',i);
    end
end

% Add '_chl' to every rxn of chl_only model
for i = 1:length(model_chl_only.rxns)
    model_chl_only.rxns{i} = [model_chl_only.rxns{i},'_chl'];
end

% Fix all exchange reactions to match convention (negative uptake)
for i = 1:length(model_chl_only.rxns)
    if length(find(model_chl_only.S(:,i))) == 1
        idx = find(model_chl_only.S(:,i));
        
        if model_chl_only.S(idx,i) > 0
            model_chl_only.S(idx,i) = -model_chl_only.S(idx,i);
            lb = model_chl_only.lb(i);
            ub = model_chl_only.ub(i);
            model_chl_only.lb(i) = -ub;
            model_chl_only.ub(i) = -lb;
        end
    end
end

clear idx ub lb i j baseLen;

% =========================================================================
%% Step 4: Merge model_chl_only to model_cyt
% =========================================================================
%   1. For exchange reactions in model_chl_only:
%       a. if rxn# found in tr_mets_map, change the exchange reaction to a
%       transport reaction between [h] and [H]
%       b. if rxn# not found in tr_mets_map but in essExBool, keep the
%       exchange as it is
%       c. if rxn# not found in tr_mets_map or essExBool, keep the exchange
%       but change its both bounds to 0
%   2. Add other reactions directly

for i = 1:length(model_chl_only.rxns)
    
%   exchange rxns
    if length(find(model_chl_only.S(:,i))) == 1
        trMet = model_chl_only.mets{find(model_chl_only.S(:,i))};
        
%       If rxn no. found in tr_mets_map, add straight in
        if length(find(tr_mets_map == i)) == 1 
            
            idx = find(tr_mets_map == i);
            cytMet = [erase(tr_mets_cyt{idx},'[h]'),'[c]'];
            
            model_cyt = addReaction(model_cyt,['Tr_',tr_mets_cyt{idx},'-[H]'],...
                'metaboliteList',{trMet,cytMet},...
                'stoichCoeffList',[-1,1],...
                'lowerBound',model_chl_only.lb(i),...
                'upperBound',model_chl_only.ub(i));
%             model_cyt = addReaction(model_cyt,['Tr_',tr_mets_cyt{idx},'-[H]'],...
%                 'metaboliteList',{cytMet,trMet},...
%                 'stoichCoeffList',[-1,1],...
%                 'lowerBound',-model_chl_only.ub(i),...
%                 'upperBound',-model_chl_only.lb(i));
            model_cyt.rules{length(model_cyt.rules)} = newRules{i};
            
        elseif ~any(tr_mets_map == i) % not found in tr_mets_map
            if i == 557 % Allow photon exchange
                model_cyt = addReaction(model_cyt,['Tr_',trMet,'_chl'],...
                    'metaboliteList',{trMet},...
                    'stoichCoeffList',[-1],...
                    'lowerBound',model_chl_only.lb(i),...
                    'upperBound',model_chl_only.ub(i));
                model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                fprintf('Essential exchange added to chl: rxn %d %s\n',i,['Tr_',trMet,'_chl']);
                
            else % Not found in cyt and isn't essential
                if i == 607 % ala[h] is not found in cre model but lethal to chl model. Just add straight in
                    model_cyt = addReaction(model_cyt,['Tr_',trMet,'-[H]'],...
                        'metaboliteList',{trMet,'ala_L[c]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                    
                elseif i == 609 % same for arg
                    model_cyt = addReaction(model_cyt,['Tr_',trMet,'-[H]'],...
                        'metaboliteList',{trMet,'arg_L[c]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                    
                elseif i == 611 % same for asn
                    model_cyt = addReaction(model_cyt,['Tr_',trMet,'-[H]'],...
                        'metaboliteList',{trMet,'asn_L[c]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                    
                elseif i == 615 % same for pro
                    model_cyt = addReaction(model_cyt,['Tr_',trMet,'-[H]'],...
                        'metaboliteList',{trMet,'pro_L[c]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};

                elseif i == 740 % proline
                    model_cyt = addReaction(model_cyt,['Tr_',trMet,'-[H]'],...
                        'metaboliteList',{trMet,'lys_L[c]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};

%               Allows transport of free FA C16:0, C18:0, C18:1 out of chl
                
                    
%               There's no 18:2 acylglycerols in cre but chl is asking for
%               it... Also no C20
%               From C160 (Hexadecanoate) -> C180: ACP-synthetase(C16),
%               ACP-synthetase(C18), reductase, dehydratase, reductase

%               source: https://www.genome.jp/pathway/map01040+C21935
                
%               c182coa: (9Z,12Z)-Octadecadienoyl-CoA
                %{
                elseif i == 646
                    model_cyt = addMetabolite(model_cyt,'ocdce912coa[c]',...
                        'metName','(9Z,12Z)-Octadecadienoyl-CoA',...
                        'metFormula','C39H66N7O17P3S');
                    model_cyt = addReaction(model_cyt,'oleoyl-CoA delta12-desaturase',...
                        'reactionName','oleoyl-CoA delta12-desaturase',...
                        'metaboliteList',{'focytb5[c]','h[c]','o2[c]','ocdce9coa[c]','ficytb5[c]','h2o[c]','ocdce912coa[c]'},...
                        'stoichCoeffList',[-2,-2,-1,-1,2,2,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'Tr_c182coa[h]-[H]',...
                        'metaboliteList',{'ocdce912coa[c]','c182coa[E]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                    
%               c183(3)coa: (9Z,12Z,15Z)-Octadecatrienoyl-CoA
                elseif i == 649
                    model_cyt = addMetabolite(model_cyt,'ocdce91215coa[c]',...
                        'metName','(9Z,12Z,15Z)-Octadecatrienoyl-CoA',...
                        'metFormula','C39H64N7O17P3S');
                    model_cyt = addReaction(model_cyt,'linoleoyl-CoA delta15-desaturase',...
                        'reactionName','linoleoyl-CoA delta15-desaturase',...
                        'metaboliteList',{'focytb5[c]','h[c]','o2[c]','ocdce912coa[c]','ficytb5[c]','h2o[c]','ocdce91215coa[c]'},...
                        'stoichCoeffList',[-2,-2,-1,-1,2,2,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'Tr_c183(3)coa[h]-[H]',...
                        'metaboliteList',{'ocdce91215coa[c]','c183(3)coa[E]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                
%               c204(6)coa: (5Z,8Z,11Z,14Z)-Icosatetraenoyl-CoA
%                   Problem is its in a completely different family...so
%                   not even compatible with the pathway im using
                elseif i == 652
                    model_cyt = addMetabolite(model_cyt,'ocdce691215coa[c]',...
                        'metName','(6Z,9Z,12Z,15Z)-Octadecatetraenoyl-CoA',...
                        'metFormula','C39H62N7O17P3S');
                    model_cyt = addReaction(model_cyt,'alpha-Linolenoyl-CoA delta6-desaturase',...
                        'reactionName','alpha-Linolenoyl-CoA delta6-desaturase',...
                        'metaboliteList',{'focytb5[c]','h[c]','o2[c]','ocdce91215coa[c]','ficytb5[c]','h2o[c]','ocdce691215coa[c]'},...
                        'stoichCoeffList',[-2,-2,-1,-1,2,2,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    
                    model_cyt = addMetabolite(model_cyt,'ictte8111417coa[c]',...
                        'metName','(8Z,11Z,14Z,17Z)-Icosatetraenoyl-CoA',...
                        'metFormula','C41H66N7O17P3S');
                    model_cyt = addReaction(model_cyt,'3OACOAS20',... % elongation to C20
                        'reactionName','3-oxoacyl-CoA synthase (20:4)',...
                        'metaboliteList',{'malcoa[c]','ocdce691215coa[c]','3oodcoa20[c]','co2[c]','coa[c]'},...
                        'stoichCoeffList',[-1,-1,1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'3OACOAR20',... % reduction 1
                        'reactionName','3-oxoacyl-CoA reductase (20:4)',...
                        'metaboliteList',{'3oodcoa20[c]','h[c]','nadph[c]','3hodcoa20[c]','nadp[c]'},...
                        'stoichCoeffList',[-1,-1,-1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'ECOAH820',... % dehydration
                        'reactionName','3-hydroxyacyl-CoA dehydratase (20:4)',...
                        'metaboliteList',{'3hodcoa20[c]','h2o[c]','od2coa20[c]'},...
                        'stoichCoeffList',[-1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'ECOAR20',... % reduction 2
                        'reactionName','trans-2-enoyl-CoA reductase (20:4)',...
                        'metaboliteList',{'h[c]','nadph[c]','od2coa20[c]','nadp[c]','ictte8111417coa[c]'},...
                        'stoichCoeffList',[-1,-1,-1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    
                    model_cyt = addReaction(model_cyt,'Tr_c204(6)coa[h]-[H]',...
                        'metaboliteList',{'ictte8111417coa[c]','c204(6)coa[E]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                
%               c205(3)coa: (5Z,8Z,11Z,14Z,17Z)-Icosapentaenoyl-CoA
                elseif i == 655
                    model_cyt = addMetabolite(model_cyt,'ictte58111417coa[c]',...
                        'metName','(5Z,8Z,11Z,14Z,17Z)-Icosatetraenoyl-CoA',...
                        'metFormula','C41H64N7O17P3S');
                    model_cyt = addReaction(model_cyt,'icosapentaenoyl-CoA delta5-desaturase',...
                        'reactionName','icosapentaenoyl-CoA delta5-desaturase',...
                        'metaboliteList',{'focytb5[c]','h[c]','o2[c]','ictte8111417coa[c]','ficytb5[c]','h2o[c]','ictte58111417coa[c]'},...
                        'stoichCoeffList',[-2,-2,-1,-1,2,2,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'Tr_c205(3)coa[h]-[H]',...
                        'metaboliteList',{'ictte58111417coa[c]','c205(3)coa[E]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                    
%               dhacoa: (4Z,7Z,10Z,13Z,16Z,19Z)-Docosahexaenoyl-CoA
                elseif i == 675
                    model_cyt = addMetabolite(model_cyt,'dcpte710131619coa[c]',...
                        'metName','(7Z,10Z,13Z,16Z,19Z)-Docosapentaenoyl-CoA',...
                        'metFormula','C43H68N7O17P3S');
                    
                    model_cyt = addReaction(model_cyt,'3OACOAS22',... % elongation to C22
                        'reactionName','3-oxoacyl-CoA synthase (22:5)',...
                        'metaboliteList',{'malcoa[c]','ictte58111417coa[c]','3oodcoa22[c]','co2[c]','coa[c]'},...
                        'stoichCoeffList',[-1,-1,1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'3OACOAR22',... % reduction 1
                        'reactionName','3-oxoacyl-CoA reductase (22:5)',...
                        'metaboliteList',{'3oodcoa22[c]','h[c]','nadph[c]','3hodcoa22[c]','nadp[c]'},...
                        'stoichCoeffList',[-1,-1,-1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'ECOAH822',... % dehydration
                        'reactionName','3-hydroxyacyl-CoA dehydratase (22:5)',...
                        'metaboliteList',{'3hodcoa22[c]','h2o[c]','od2coa22[c]'},...
                        'stoichCoeffList',[-1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'ECOAR22',... % reduction 2
                        'reactionName','trans-2-enoyl-CoA reductase (22:5)',...
                        'metaboliteList',{'h[c]','nadph[c]','od2coa22[c]','nadp[c]','dcpte710131619coa[c]'},...
                        'stoichCoeffList',[-1,-1,-1,1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    
                    model_cyt = addMetabolite(model_cyt,'dcpte4710131619coa[c]',...
                        'metName','(4Z,7Z,10Z,13Z,16Z,19Z)-Docosapentaenoyl-CoA',...
                        'metFormula','C43H66N7O17P3S');
                    model_cyt = addReaction(model_cyt,'docosapentaenoyl-CoA delta4-desaturase',...
                        'reactionName','docosapentaenoyl-CoA delta4-desaturase',...
                        'metaboliteList',{'focytb5[c]','h[c]','o2[c]','dcpte710131619coa[c]','ficytb5[c]','h2o[c]','dcpte4710131619coa[c]'},...
                        'stoichCoeffList',[-2,-2,-1,-1,2,2,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    model_cyt = addReaction(model_cyt,'Tr_dhacoa[h]-[H]',...
                        'metaboliteList',{'dcpte4710131619coa[c]','dhacoa[E]'},...
                        'stoichCoeffList',[-1,1],...
                        'lowerBound',-1000,...
                        'upperBound',1000);
                    
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                %}
%               Else close lower bound
                else
                    model_cyt = addReaction(model_cyt,['Tr_',trMet,'_chl'],...
                        'metaboliteList',{trMet},...
                        'stoichCoeffList',[-1],...
                        'lowerBound',0,...
                        'upperBound',1000);
                    model_cyt.rules{length(model_cyt.rules)} = newRules{i};
                    
                    fprintf('Chl exchange not covered: %s\n',trMet);
%                     fprintf('Closed inessential exchange: rxn %d %s\n',i,trMet);
                end
            end
            
        elseif length(find(tr_mets_map == i)) > 1 % safeguard
            error('Duplications exists in tr_mets_map\n');
        end
        
%   other reactions just added straight in
    else
        metList = model_chl_only.mets(find(model_chl_only.S(:,i)));
        coefList = model_chl_only.S(find(model_chl_only.S(:,i)),i);

        model_cyt = addReaction(model_cyt,model_chl_only.rxns{i},...
            'metaboliteList',metList,...
            'stoichCoeffList',coefList,...
            'lowerBound',model_chl_only.lb(i),...
            'upperBound',model_chl_only.ub(i));
        
        model_cyt.rules{length(model_cyt.rules)} = newRules{i};
    end
end

clear idx trMet coefList metList cytMet;

% Sync two biomass
model_cyt = addMetabolite(model_cyt,'bmSync');
model_cyt.S(find(strcmp(model_cyt.mets,'bmSync')),find(strcmp(model_cyt.rxns,'BIOMASS_at_Chl_bio_chl'))) = 1;
model_cyt.S(find(strcmp(model_cyt.mets,'bmSync')),find(strcmp(model_cyt.rxns,'Biomass_Chlamy_auto'))) = -1;

% f6p_B is imported directly from chl
%   Issue: f6p_B doesn't exist in chl model, it's indifferent from f6p
%       the f6p_b producing rxn (TAh) is NanoG0511 in chl but produce f6p
% model_cyt = addReaction(model_cyt,'F6PBGEN',...
%     'metaboliteList',{'f6p[H]','f6p_B[H]'},...
%     'stoichCoeffList',[-1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000); % orphan reaction? 
% model_cyt = addReaction(model_cyt,'Tr_f6p_B[h]-[H]',...
%     'metaboliteList',{'f6p_B[h]','f6p_B[H]'},...
%     'stoichCoeffList',[-1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000);

% Reduced glutathione
% model_cyt = addReaction(model_cyt,'Tr_gthrd[h]-[H]',...
%     'metaboliteList',{'gthrd[h]','gluth[H]'},...
%     'stoichCoeffList',[-1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000);

% SO3 isn't a metabolite in cre
% model_cyt = addExchangeRxn(model_cyt,'so3[H]',-5,1000);
model_cyt = addReaction(model_cyt,'Tr_hso3[h]-[H]',...
    'metaboliteList',{'so3[H]','h[H]','hso3[c]'},...
    'stoichCoeffList',[-1,-1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);
% R00533 convert so4 to so3...
% model_cyt = addReaction(model_cyt,'R00533',...
%     'metaboliteList',{'hso3[c]','o2[c]','h2o[c]','h2o2[c]',''},...
%     'stoichCoeffList',[-1,1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000);

% Riboflavin
% model_cyt = addReaction(model_cyt,'Tr_gtp[h]-[H]',...
%     'metaboliteList',{'gtp[c]','gtp[H]'},...
%     'stoichCoeffList',[-1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000);

% Its something related to gtp that is missing...
% model_cyt = addExchangeRxn(model_cyt,'gmp[c]',-0.03,0);
% model_cyt = addExchangeRxn(model_cyt,'gtp[c]',-0.5,0); % not sure whats happening

% ocdcea[h] <-> c181[H]
%   difference: 18:1(11Z) vs 18:1(9Z)
% model_cyt = addReaction(model_cyt,'Tr_ocdcea[h]-[H]',...
%     'metaboliteList',{'ocdcea[h]','c181[H]'},...
%     'stoichCoeffList',[-1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000);

% sqdg18111Z160[h] and sqdg1819Z160[h]
%   ? 1:1 mixture of 18:1 and 16:0
model_cyt = addReaction(model_cyt,'sqdg181160Form',...
    'metaboliteList',{'sqdg181160[H]','sqdg181[H]','sqdg160[H]'},...
    'stoichCoeffList',[-2,1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);
model_cyt = addReaction(model_cyt,'Tr_sqdg18111Z160[h]-[H]',...
    'metaboliteList',{'sqdg18111Z160[h]','sqdg181160[H]'},...
    'stoichCoeffList',[-1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);
model_cyt = addReaction(model_cyt,'Tr_sqdg1819Z160[h]-[H]',...
    'metaboliteList',{'sqdg1819Z160[h]','sqdg181160[H]'},...
    'stoichCoeffList',[-1,1],...
    'lowerBound',-1000,...
    'upperBound',1000);

% Gap filling attempt to fix gtp problem

% Added 5 reactions: TAh(NanoG0511) RPIh(NanoG0512) RPEh(NanoG0514) TKT1h(NanoG0518) TKT2h(NanoG0516)
% Chl submodel is not missing these rxn, so it must be exchange rxns
% model_cyt = addReaction(model_cyt,'Tr_g3p[h]-[H]',...
%     'metaboliteList',{'g3p[h]','g3p[H]'},...
%     'stoichCoeffList',[-1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000);
% model_cyt = addReaction(model_cyt,'Tr_r5p[h]-[H]',...
%     'metaboliteList',{'r5p[h]','rib5p[H]'},...
%     'stoichCoeffList',[-1,1],...
%     'lowerBound',-1000,...
%     'upperBound',1000); % yeah here's the issue

% model_cyt = gapFillFromU(model_cyt,gpStruct,'Biomass_Chlamy_auto',0.01);

% Refine the transport reactions
% Add a proton symport for each one below
list = {'Tr_ile_L[h]-[H]','Tr_leu_L[h]-[H]','Tr_thr_L[h]-[H]','Tr_trp_L[h]-[H]',...
    'Tr_tyr_L[h]-[H]','Tr_val_L[h]-[H]','Tr_met_L[h]-[H]','Tr_glu_L[h]-[H]'};

for i = 1:length(list)
    idx = find(strcmp(model_cyt.rxns,list{i}));
    model_cyt.S(765,idx) = -1;
    model_cyt.S(1488,idx) = 1;
end

clear list;

% Add starch reactions to Chloroplast
%   this may become the carbon source in the dark condition
model_cyt = addReaction(model_cyt,'GLPThi',...
    'reactionName','glucose-1-phosphate adenylyltransferase (chloroplast)',...
    'metaboliteList',{'atp[H]','g1p[H]','adpglc[H]','ppi[H]'},...
    'stoichCoeffList',[-1,-1,1,1],...
    'lowerBound',0,'upperBound',1000,...
    'geneRule','(( Cre13.g567950 or Cre07.g331300 or Cre16.g683450 ) and Cre03.g188250 )');

model_cyt = addReaction(model_cyt,'STARCH300S',...
    'reactionName','starch synthase (300 glc units)',...
    'metaboliteList',{'adpglc[H]','h2o[H]','adp[H]','h[H]','starch300[H]'},...
    'stoichCoeffList',[-300,-1,300,300,1],...
    'lowerBound',0,'upperBound',1000,...
    'geneRule','(( Cre06.g289850 or Cre06.g270100 or Cre10.g444700 ) and ( Cre12.g521700 or Cre03.g185250 or Cre16.g665800 or Cre06.g282000 or Cre13.g579598 or Cre13.g579582 or Cre04.g215150))');
model_cyt = addExchangeRxn(model_cyt,'starch300[H]',0,1000);
model_cyt = addReaction(model_cyt,'STARCH300DEGR2',...
    'reactionName','degradation of starch300 by phosphorylase, amylase, dextrinase, maltase',...
    'metaboliteList',{'h2o[H]','pi[H]','starch300[H]','g1p[H]','glc[H]'},...
    'stoichCoeffList',[-49,-250,-1,250,50],...
    'lowerBound',0,...
    'upperBound',1000);
model_cyt = addReaction(model_cyt,'STARCH300DEGR',...
    'reactionName','degradation of starch300 by phosphorylase, amylase, dextrinase, maltase',...
    'metaboliteList',{'h2o[H]','pi[H]','starch300[H]','g1p[H]','glc[H]'},...
    'stoichCoeffList',[-74,-225,-1,225,75],...
    'lowerBound',0,...
    'upperBound',1000);

model_cyt = rmfield(model_cyt,'grRules');
model_cyt = creategrRulesField(model_cyt);
clear gn i idx;

%% Step 5: Get Cplx Stoich From Chlamycyc
% model_cyt = mapRxnsToBioCyc(model_cyt,chlamycyc,2449);

%% Step 6: Manual Curation and Formulation

% fix compartment symbols
model_cyt.comps{5} = 'H';
model_cyt.comps{8} = 'S';
model_cyt.comps{9} = 'U';

% Looking pretty okay
% correct complex subunits
%   rubisco
model_cyt.grRules{find(strcmp(model_cyt.rxns,'NanoG0589_chl'))} = '( ChreCp049 or ( ChreCp049 and Cre02.g120150 ))';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'NanoG0460_chl'))} = '( ChreCp049 or ( ChreCp049 and Cre02.g120150 ))';
%   PS I
model_cyt.grRules{find(strcmp(model_cyt.rxns,'P700A0_chl'))} = '( Cre12.g508750 and Cre11.g467573 and Cre10.g452050 and Cre06.g283050 and Cre09.g412100 and Cre03.g165100 and Cre12.g560950 and Cre07.g330250 and Cre05.g238332 and Cre02.g082500 and Cre17.g724300 and Cre07.g334550 and Cre12.g486300 and Cre10.g420350 and ChreCp019 and ChreCp048 and ChreCp061 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'PCP700_chl'))} = '( Cre12.g508750 and Cre11.g467573 and Cre10.g452050 and Cre06.g283050 and Cre09.g412100 and Cre03.g165100 and Cre12.g560950 and Cre07.g330250 and Cre05.g238332 and Cre02.g082500 and Cre17.g724300 and Cre07.g334550 and Cre12.g486300 and Cre10.g420350 and ChreCp019 and ChreCp048 and ChreCp061 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'A0A1_chl'))} = '( Cre12.g508750 and Cre11.g467573 and Cre10.g452050 and Cre06.g283050 and Cre09.g412100 and Cre03.g165100 and Cre12.g560950 and Cre07.g330250 and Cre05.g238332 and Cre02.g082500 and Cre17.g724300 and Cre07.g334550 and Cre12.g486300 and Cre10.g420350 and ChreCp019 and ChreCp048 and ChreCp061 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'A1FX_chl'))} = '( Cre12.g508750 and Cre11.g467573 and Cre10.g452050 and Cre06.g283050 and Cre09.g412100 and Cre03.g165100 and Cre12.g560950 and Cre07.g330250 and Cre05.g238332 and Cre02.g082500 and Cre17.g724300 and Cre07.g334550 and Cre12.g486300 and Cre10.g420350 and ChreCp019 and ChreCp048 and ChreCp061 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'FXFB_chl'))} = '( Cre12.g508750 and Cre11.g467573 and Cre10.g452050 and Cre06.g283050 and Cre09.g412100 and Cre03.g165100 and Cre12.g560950 and Cre07.g330250 and Cre05.g238332 and Cre02.g082500 and Cre17.g724300 and Cre07.g334550 and Cre12.g486300 and Cre10.g420350 and ChreCp019 and ChreCp048 and ChreCp061 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'FBFA_chl'))} = '( Cre12.g508750 and Cre11.g467573 and Cre10.g452050 and Cre06.g283050 and Cre09.g412100 and Cre03.g165100 and Cre12.g560950 and Cre07.g330250 and Cre05.g238332 and Cre02.g082500 and Cre17.g724300 and Cre07.g334550 and Cre12.g486300 and Cre10.g420350 and ChreCp019 and ChreCp048 and ChreCp061 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'FAFD_chl'))} = '( Cre12.g508750 and Cre11.g467573 and Cre10.g452050 and Cre06.g283050 and Cre09.g412100 and Cre03.g165100 and Cre12.g560950 and Cre07.g330250 and Cre05.g238332 and Cre02.g082500 and Cre17.g724300 and Cre07.g334550 and Cre12.g486300 and Cre10.g420350 and ChreCp019 and ChreCp048 and ChreCp061 )';
%   PS II
model_cyt.grRules{find(strcmp(model_cyt.rxns,'S0S1_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'S1S2_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'S2S3_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'S3S4_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'S4S0_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'P680P_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'YZP680_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'PQA_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'QAQB1_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'QAQB2_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'QBPQH2_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
model_cyt.grRules{find(strcmp(model_cyt.rxns,'PQPSII_chl'))} = '( Cre17.g720250 and Cre16.g673650 and Cre01.g066917 and Cre12.g548400 and Cre04.g232104 and Cre06.g283950 and Cre03.g156900 and Cre06.g285250 and Cre12.g548950 and Cre06.g284250 and Cre06.g284200 and Cre02.g110750 and Cre12.g550850 and Cre08.g372450 and Cre09.g396213 and ChreCp027 and ChreCp066 and ChreCp004 and ChreCp029 and ChreCp063 and ChreCp044 and ChreCp026 and ChreCp040 and ChreCp064 and ChreCp032 and ChreCp057 and Cre06.g261000 and ChreCp031 )';
%   Cytochrome b6f
model_cyt.grRules{find(strcmp(model_cyt.rxns,'CEF_chl'))} = '( Cre12.g546150 and Cre16.g650100 and Cre11.g467689 and ChreCp001 and ChreCp002 and ChreCp008 and ChreCp045 and ChreCp068 )';
%   CF0F1 ATP Synthase
model_cyt.grRules{find(strcmp(model_cyt.rxns,'ATPSh_chl'))} = '( ChreCp053 and ChreCp054 and ChreCp062 and Cre11.g481450 and Cre11.g467569 and Cre06.g259900 and ChreCp023 and ChreCp050 and ChreCp058 )';
%   Complex I
model_cyt.grRules{find(strcmp(model_cyt.rxns,'NADHOR'))} = '( Cre10.g422600 and Cre07.g327400 and Cre09.g405850 and Cre13.g568800 and Cre05.g240800 and Cre16.g673109 and Cre12.g511200 and Cre13.g571150 and Cre16.g681700 and Cre16.g679500 and Cre14.g617826 and Cre06.g278188 and Cre11.g467668 and Cre06.g267200 and Cre08.g378050 and Cre03.g146247 and Cre10.g434450 and Cre03.g178250 and Cre03.g204650 and Cre12.g555150 and Cre08.g378550 and Cre11.g467767 and Cre16.g664600 and Cre05.g232200 and Cre05.g244901 and Cre12.g555250 and Cre07.g333900 and Cre10.g459750 and ChrepMp02 and ChrepMp03 and ChrepMp05 and ChrepMp06 and ChrepMp07 )';
%   Complex III
model_cyt.grRules{find(strcmp(model_cyt.rxns,'CYOR_q8_m'))} = '( Cre01.g051900 and Cre15.g638500 and Cre03.g156950 and Cre11.g468950 and Cre09.g409150 and Cre06.g262700 and ChrepMp01 and Cre17.g722800 )';
%   Complex IV
model_cyt.grRules{find(strcmp(model_cyt.rxns,'CYOO6m'))} = '( Cre12.g537450 and Cre16.g691850 and Cre13.g567600 and Cre06.g304350 and ChrepMp04 and Cre03.g157700 and Cre03.g154350 )';
%   Complex V
model_cyt.grRules{find(strcmp(model_cyt.rxns,'ATPSm'))} = '( Cre10.g420700 and Cre01.g018800 and Cre11.g467707 and Cre16.g680000 and Cre10.g419050 and Cre17.g732000 and Cre15.g635850 and Cre17.g731950 and Cre02.g116750 and Cre07.g338050 and Cre13.g581600 and Cre17.g721300 and Cre02.g079800 and Cre09.g395350 and Cre09.g402300 and Cre09.g415550 and Cre09.g416150 and Cre07.g340350 )';
%   ADP-glucose pyrophosphorylase
model_cyt.grRules{find(strcmp(model_cyt.rxns,'GLPThi'))} = '( ( Cre03.g188250 and Cre13.g567950 ) or ( Cre03.g188250 and Cre01.g040050 ) )';

% Followings are curations from previous iterations


% Update model.rules from model.grRules
model_cyt = rmfield(model_cyt,'rules');
model_cyt = generateRules(model_cyt);

% Apply protein-constraints
if ~exist('model_merged','var')
    [model_merged,fullProtein,fullCplx,C_matrix,K_matrix,fullProteinMM] = pcModel(model_cyt,'Chlamydomonas_reinhardtii_full.txt',150);

%   adjust C_matrix
%       rubisco: CPLX4LZ-41
    C_matrix(180,1064) = 8;
%       rubisco: CPLX4LZ-34
    C_matrix(180,1065) = 8;
    C_matrix(182,1065) = 8;
%       PSII: CPLX4LZ-235
    C_matrix(854,1181) = 3;
    C_matrix([828,839,825,829,837,834,827,832,838,831,836,845,830],1181) = 2;
%       cytochrome b6f: CPLX4LZ-294
    C_matrix([788,789,790,791,792,794,795,797],1182) = 2;
    C_matrix([788,789,790,791,792,794,795,797],1199) = 2;
%       CF0F1 ATP Synthase: CPLX4LZ-15
    C_matrix(781,1184) = 13;
    C_matrix([780,783],1184) = 3;
%       ADP-glucose pyrophosphorylase: CPLX-8665
    C_matrix([1122,1124],1200) = 2;
    C_matrix([1122,1198],1201) = 2;

%   estimate Keff and update model
    K_matrix = estimateKeffFromMW(C_matrix,K_matrix,fullProteinMM);
    model_merged = adjustStoichAndKeff(model_merged,C_matrix,K_matrix);
end

model_merged = changeRxnBounds(model_merged,'EX_ac_e',0,'l');
model_merged = changeObjective(model_merged,'Biomass_Chlamy_auto');
FBAsol_merged = optimizeCbModel(model_merged,'max');

if (FBAsol_merged.stat == 1) && (FBAsol_merged.f > 1e-6)
    disp('Merged model feasible');
    
elseif FBAsol_merged.stat == 1
    disp('Merged model growth rate = 0');
else
    disp('Merged model infeasible');
end

% Plotting
% Plot exchange between chloroplast and cytosol
x = {};
Y = [];
for i = 1:length(model_cyt.rxns)
    if (contains(model_cyt.rxns{i},'Tr_') && contains(model_cyt.rxns{i},']-[') && (abs(FBAsol_merged.v(i))>1e-2))
        x{length(x)+1} = model_cyt.rxns{i};
        Y(length(Y)+1) = FBAsol_merged.v(i);
    end
end

figure;
title('Chl - Cyt translocation');
X = categorical(x);
X = reordercats(X,x);
bar(X,Y);
clear x X Y;

% Plot exchange reactions of chl
x = {};
Y = [];
for i = 1:length(model_cyt.rxns)
    if ((length(find(model_cyt.S(:,i)))==1) && (abs(FBAsol_merged.v(i))>1e-2))
        x{length(x)+1} = model_cyt.rxns{i};
        Y(length(Y)+1) = FBAsol_merged.v(i);
    end
end

figure;
title('Exchange Rxns');
X = categorical(x);
X = reordercats(X,x);
bar(X,Y);
clear x X Y;

clear fd idx mapIdx;

save('model_merged','model_merged','fullProtein','fullCplx','C_matrix','K_matrix','fullProteinMM');

% autotrophic, mixotrophic, and heterotrophic optimal solution
model_auto = model_merged;
model_mixo = changeRxnBounds(model_merged,'EX_ac_e',-2,'l');
model_hetero = changeRxnBounds(model_merged,'EX_ac_e',-1000,'l');
FBAsol_auto = optimizeCbModel(model_auto,'max');
FBAsol_mixo = optimizeCbModel(model_mixo,'max');
FBAsol_hetero = optimizeCbModel(model_hetero,'max');

fullCplxMM = C_matrix'*fullProteinMM;
fullCplxFormIdx = find(startsWith(model_merged.rxns,'cplxForm_'));

% fl = cell(length(fullProtein),2);
% proteinExIdx = find(startsWith(model_auto.rxns,'EX_protein_'));
% 
% for i = 1:length(proteinExIdx)
%     idx = find(startsWith(fst.Header,fullProtein{i}));
%     if isempty(idx)
%         fl{i,1} = fullProtein{i};
%     elseif ~contains(fst.Header{idx(1)},'[old_locus_tag=')
%         fl{i,1} = fullProtein{i};
%     else
%         ln = split(fst.Header{idx(1)},'[old_locus_tag=');
%         ln = ln{2};
%         ln = split(ln,']');
%         fl{i,1} = ln{1};
%     end
% 
%     fl{i,2} = abs(FBAsol_hetero.v(proteinExIdx(i)))*1000;
% end
% 
% writecell(fl,'Cre_3.txt','Delimiter','\t');

%{
% =========================================================================
%% Validation
% =========================================================================
% Try phosphate depletion scenario...
if ~exist('rnaseq_pi_ori','var')
    rnaseq_pi_ori = readtable('GSE56505_Expression_RPKM_2014March');
end
rnaseq_pi = rnaseq_pi_ori;

rnaseq_pi.Properties.VariableNames{6} = 'piDeprived';
rnaseq_pi.Properties.VariableNames{7} = 'piReplete';

%   Normalize so their means are the same
rnaseq_pi.piDeprived = rnaseq_pi.piDeprived * mean(rnaseq_pi.piReplete)/mean(rnaseq_pi.piDeprived);

%   Convert them to count
rnaseq_pi.piDeprived = round(rnaseq_pi.piDeprived*10);
rnaseq_pi.piReplete = round(rnaseq_pi.piReplete*10);

%   If zero is found, assign 1
for i = 1:height(rnaseq_pi)
    if rnaseq_pi.piDeprived(i) == 0
        rnaseq_pi.piDeprived(i) = 1;
    end

    if rnaseq_pi.piReplete(i) == 0
        rnaseq_pi.piReplete(i) = 1;
    end
end


% Remove everything with too little count
rm = [];
for i = 1:height(rnaseq_pi)
    if rnaseq_pi.piDeprived(i) + rnaseq_pi.piReplete(i) < 30
        rm(length(rm)+1,1) = i;
    end
end
rnaseq_pi(rm,:) = [];
clear rm;

% Adding log2FC
for i = 1:height(rnaseq_pi)
    rnaseq_pi{i,8} = log(rnaseq_pi.piDeprived(i)/rnaseq_pi.piReplete(i))/log(2);
end

rnaseq_pi.Properties.VariableNames{8} = 'log2FC';

% Adding a p value column to it

for i = 1:height(rnaseq_pi)
    df = binocdf(rnaseq_pi.piDeprived(i),(rnaseq_pi.piReplete(i)+rnaseq_pi.piDeprived(i)),0.5);
    
    if df >= 0.5
        rnaseq_pi{i,9} = 1 - df;
    else
        rnaseq_pi{i,9} = df;
    end
end

rnaseq_pi.Properties.VariableNames{9} = 'pvalue';

% Extract a table for genes of significant change + large FC (>=1)
rnaseq_sc = rnaseq_pi;
rm = [];

for i = 1:height(rnaseq_sc)
    if abs(rnaseq_sc.log2FC(i)) < 1
        rm(length(rm)+1,1) = i;
    elseif rnaseq_sc.pvalue(i) > 0.01
        rm(length(rm)+1,1) = i;
    else
        continue;
    end
end

rnaseq_sc(rm,:) = [];

% First simulate directly and compare outcome
% TA medium...model can't any of the sugar
% model_merged_pr = model_merged;
% model_merged_pd = changeRxnBounds(model_merged,'EX_pi_e',-1e-3,'l');
% 
% FBAsol_pr = optimizeCbModel(model_merged_pr,'max');
% FBAsol_pd = optimizeCbModel(model_merged_pd,'max');
% 
% % Collecting results
% X = [];
% Y = [];
% lbl = {};
% 
% for i = 1:length(fullProtein)
%     
% %   Finding corresponding protein in rnaseq result
%     idx = 0;
%     
%     for j = 1:height(rnaseq_sc)
%         if contains(fullProtein{i},rnaseq_sc.geneName{j})
%             idx = j;
%             break;
%         end
%     end
%     
%     if idx == 0
%         continue;
%     end
%     
%     lbl{length(lbl)+1,1} = rnaseq_sc.geneName{idx};
%     Y(length(Y)+1,1) = rnaseq_sc.log2FC(idx);
%     
% %   Calculating results from model
%     idx = find(strcmp(model_merged_pr.rxns,['EX_protein_',fullProtein{i}]));
%     
%     if (abs(FBAsol_pd.v(idx)) < 1e-6) && (abs(FBAsol_pr.v(idx)) < 1e-6)
%         X(length(X)+1,1) = 0;
%     elseif abs(FBAsol_pd.v(idx)) < 1e-6
%         X(length(X)+1,1) = -5;
%     elseif abs(FBAsol_pr.v(idx)) < 1e-6
%         X(length(X)+1,1) = 5;
%     else
%         X(length(X)+1,1) = log(FBAsol_pd.v(idx)/FBAsol_pr.v(idx))/log(2);
%     end
% end
% 
% clear idx rm;
% 
% % Plot
% figure;
% scatter(X,Y);
% xlabel('Model Prediction');
% ylabel('Transcriptome');
% text(X,Y,lbl);

% Another approach is using RNAseq FC to set constrains

% MADE or TIGER by Jensen and Papin are not available
% There are at least 2 schools of thoughts:
%   1. minimize sum square error between transcriptome and model
%   2. set a threshold for highly/lowly expressed proteins and match the
%      model up as much as possible

% Use new pc model constructor
if ~exist('model_new','var')
    [model_new,fullProtein,fullCplx,C_matrix,K_matrix,fullProteinMM] = pcModel(model_cyt,'all_fasta.fasta',150);
end

% Roughly adjust K_eff using data on chlamycyc

% New script to re-adjust the model's constants based on C_matrix and 
% K_matrix, which can be modified manually based on data

% Total 89 cplx with more than 1 protein
%       21 cplx with more than 2 proteins

% Largest cplx based on current model (cplx to change):
%   Chl_protprod_chl > NADHOR(cplxI) > ATPSm(cplxV) > PSII > PSI
%   = CYOO6m(cplxIV) > CEF = ATPSh > cytb6f = CYOR(cplxIII) > Rubisco

% Several disagreements between model gene annotation and chlamycyc, looks
% like the annotation of rubisco is wrong in model

C_matrix_adj = C_matrix;

% cplxI: no need to change
% cplxV: no need to change
% PSII (cplx 1216): double every stoich coef
C_matrix_adj(:,1216) = C_matrix_adj(:,1216)*2;
% PSI: no need to change
% cplxIV: no need to change
% CEF (cplx 1232) and cytb6f (cplx 1217): double every coef
C_matrix_adj(:,1232) = C_matrix_adj(:,1232)*2;
C_matrix_adj(:,1217) = C_matrix_adj(:,1217)*2;
% ATPSh (cplx 1219): ChreCp053 * 13, ChreCp050 * 3, ChreCp058 * 3
C_matrix_adj(841,1219) = 13;
C_matrix_adj(840,1219) = 3;
C_matrix_adj(843,1219) = 3;
% cplxIII: no need to change
% Rubisco (cplx 1124): 8 times both coef
C_matrix_adj(:,1124) = C_matrix_adj(:,1124)*8;

% Update Keff 
K_matrix_adj = estimateKeffFromMW(C_matrix_adj,K_matrix,fullProteinMM);

% Update model
if ~exist('model_adj_ori','var')
    model_adj_ori = adjustStoichAndKeff(model_new,C_matrix_adj,K_matrix_adj);
end

model_adj = model_adj_ori;

% Rewrite biomass sync
model_adj = removeCOBRAConstraints(model_adj,model_adj_ori.ctrs{1});
model_adj = addMetabolite(model_adj,'biomassSync');
model_adj.S(length(model_adj.mets),1799) = 1;
model_adj.S(length(model_adj.mets),2636) = -1;

% Also there are minor mistakes in rule parsing need to be fixed...fixed

% Finding a way to overlay transcriptome
%   Either minimizing sum_ |EX_prot - k*count| 
%                  or sum_ (EX_prot - k*count)^2

% Compile a transcriptome for overlayTranscritome function...
% if ~exist('chlCreMap','var')
%     chlCreMap = readtable('chl_on_cre.txt');
% end
% 
% overlaidT_rep = cell(0,0);
% overlaidT_dep = cell(0,0);
% 
% for i = 1:length(model_adj.genes)
%     
%     genName = model_adj.genes{i};
%     overlaidT_rep{i,1} = genName;
%     overlaidT_dep{i,1} = genName;
%     
% %   Remap genes starting with ChreCp
%     if startsWith(genName,'ChreCp')
%         map = find(strcmp(chlCreMap.Var1,genName));
%         if ~isempty(map)
%             genName = chlCreMap.Var2{map(1)};
%             genName = split(genName,'|');
%             genName = genName{end};
%         end
%     end
%     
% %   find count in rnaseq_pi
%     idx = find(strcmp(rnaseq_pi.fullGeneName,genName));
%     if isempty(idx) && startsWith(genName,'Cre')
%         genName(end-4:end) = [];
%         idx = find(strcmp(rnaseq_pi.geneName,genName));
%     end
%     
% %   assign count value
%     if isempty(idx)
%         overlaidT_rep{i,2} = 0;
%         overlaidT_dep{i,2} = 0;
%     else
%         overlaidT_rep{i,2} = rnaseq_pi.piReplete(idx(1));
%         overlaidT_dep{i,2} = rnaseq_pi.piDeprived(idx(1));
%     end
% end
% 
% % 394 proteins not found...giving waivers to all of them
% waiverList = {};
% for i = 1:length(overlaidT_rep)
%     if overlaidT_rep{i,2} == 0
%         waiverList{end+1,1} = overlaidT_rep{i,1};
%     end
% end
% 
% % Try out new function of overlaying transcriptome
% % model_adj.S(4654,11771) = -0.15;
% % model_adj.S(4654,11772) = -0.15;
% 
% model_adj = changeRxnBounds(model_adj,'Biomass_Chlamy_auto',0.002,'l');
% model_adj = changeRxnBounds(model_adj,'EX_ac_e',-10,'l');
% model_adj = changeRxnBounds(model_adj,'EX_nh4_e',-10,'l');
% model_adj = changeRxnBounds(model_adj,'EX_pi_e',-10,'l');
% [FBAsol_rep,model_rep] = overlayTranscriptome(model_adj,overlaidT_rep,100,waiverList,'sqr');
% 
% model_adj = changeRxnBounds(model_adj,'EX_pi_e',-0.01,'l');
% [FBAsol_dep,model_dep] = overlayTranscriptome(model_adj,overlaidT_dep,100,waiverList,'sqr');
% 
% % Plot
% X1 = [];
% X2 = [];
% Y1 = [];
% Y2 = [];
% lbl1 = {};
% lbl2 = {};
% 
% for i = 1:length(model_adj.rxns)
%     if contains(model_adj.rxns{i},'EX_protein_') && ~any(strcmp(waiverList,erase(model_adj.rxns{i},'EX_protein_')))
%         Y1(length(Y1)+1,1) = model_rep.c(i);
%         X1(length(X1)+1,1) = -FBAsol_rep.full(i);
%         lbl1{length(lbl1)+1,1} = model_adj.rxns{i};
%     end
% end
% 
% figure;
% subplot(1,2,1);
% scatter(X1,Y1);
% % text(X1,Y1,lbl1);
% title(['Phosphate Replete, Obj = ',num2str(FBAsol_rep.obj)]);
% xlabel('Transcriptome fitting nmol/gDW');
% ylabel('Predicted nmol/gDW');
% title(['Phosphate Replete, Obj = ',num2str(FBAsol_rep.obj)]);
% 
% for i = 1:length(model_adj.rxns)
%     if contains(model_adj.rxns{i},'EX_protein_') && ~any(strcmp(waiverList,erase(model_adj.rxns{i},'EX_protein_')))
%         Y2(length(Y2)+1,1) = model_dep.c(i);
%         X2(length(X2)+1,1) = -FBAsol_dep.full(i);
%         lbl2{length(lbl2)+1,1} = model_adj.rxns{i};
%     end
% end
% 
% subplot(1,2,2);
% scatter(X2,Y2);
% % text(X2,Y2,lbl2);
% xlabel('Transcriptome fitting nmol/gDW');
% ylabel('Predicted nmol/gDW');
% title(['Phosphate Deprived, Obj = ',num2str(FBAsol_dep.obj)]);
% 
% clear idx i j genName map baseLen;

% Y >> X
%   EX_protein_Cre02.g145800.t1.2 (malate dehydrogenase, mitochondrial)
%   EX_protein_Cre12.g513200.t1.2 (enolase)
% X >> Y
%   EX_protein_Cre02.g120150.t1.2 (PPP in chl)
%   EX_protein_Cre14.g626700.t1.2 (CEF)
%   EX_protein_Cre03.g182551.t1.2 (catalyze no rxn)

% Thinking about fitting K_eff through transcriptome...
%   Sampling being the easiest method

% Notes:
%   - Only change keff of enzymes with at least one signnificant protein 
%       (protein >= 0.05% total proteome), 143 qualified enzymes
%   - All available proteins are evaluated (1155 in this case)
%   - Average will be kept at 234000 hr-1
%   - Keff varied between 25% and 175% of the original value
%   - Taking 5*[# of varied keff] samples for now

%{
% Calculate total transcripts in the model (from overlaidT_rep)
totalT = 0;

for i = 1:length(overlaidT_rep)
    totalT = totalT + overlaidT_rep{i,2};
end

% Boolean shows keffs to be perturbed
variedKeff = zeros(length(fullCplx),1);

for i = 1:length(variedKeff)
    idx = find(C_matrix_adj(:,i));
    
    for j = 1:length(idx)
        if overlaidT_rep{idx(j),2} > totalT/2000
            variedKeff(i) = 1;
        end
    end
end

clear idx i j;

% Record the average rate constants of 143 enzymes to be varied. This avg
% must be kept throughout perturbing
K_vector_base = zeros(length(fullCplx),1);

for i = 1:length(K_vector_base)
    K_vector_base(i) = sum(K_matrix_adj(:,i))/length(find(K_matrix_adj(:,i)));
end

avgKeff = mean(K_vector_base(find(variedKeff)));

% Now there are confusions on the objective function...either bm or SSE
%   ideally optimizing for biomass

model_adj = changeRxnBounds(model_adj,'EX_pi_e',-10,'l');

if ~exist('record_keffscale','var')
    % Record
    record_flux = zeros(length(model_adj.rxns),5*length(find(variedKeff)));
    record_keffscale = zeros(length(fullCplx),5*length(find(variedKeff)));
    record_obj = zeros(1,5*length(find(variedKeff)));

    % Sampling...
    for i = 1:5*length(find(variedKeff))
        model_alt = model_adj;

    %   Take an random set of 143 values in [0.25,1.75]
    %       0.25 means keff is reduced by 75%
    %       1.75 means keff is increased by 75%
        variedScale = zeros(length(find(variedKeff)),1);
        for j = 1:length(variedScale)
            variedScale(j) = random('Uniform',0.25,1.75);
        end

    %   Make sure mean is 1
        mn = mean(variedScale);
        for j = 1:length(variedScale)
            variedScale(j) = variedScale(j)/mn;
        end

    %   Assign scales to model and record
        idx = 1;
        for j = 1:length(fullCplx)
            if ~variedKeff(j)
                record_keffscale(j,i) = 1;
            else
                record_keffscale(j,i) = variedScale(idx);

    %           First find all enzymeForm rxns
                cplxIdx = find(strcmp(model_alt.mets,['cplx_',fullCplx{j}]));
                rxnIdx = find(model_alt.S(cplxIdx,:)<0);
                for k = 1:length(rxnIdx)
                    model_alt.S(cplxIdx,rxnIdx(k)) = model_alt.S(cplxIdx,rxnIdx(k))/variedScale(idx);
                end

                idx = idx + 1;
            end
        end

    %   Optimize and collect results
    %     FBAsol_alt = optimizeCbModel(model_alt,'max');
        FBAsol_alt = overlayTranscriptome(model_alt,overlaidT_rep,100,waiverList,'sqr');
        record_flux(:,i) = FBAsol_alt.full;
        record_obj(i) = FBAsol_alt.obj;
    end
end

% See if large complex's keff affects obj...not really
%   enzyme 550/551: ATPSm
%   enzyme 554: cytochrome c oxidase Complex IV
%   enzyme 560: ubiquinone oxidoreductase Complex I
%   enzyme 1216: PSII is not perturbed......
%   enzyme 1217: electron transport system in PS
%   enzyme 1218: PSI
%   enzyme 1219: ATPSh
%   enzyme 1221: chl specific proteins
%   enzyme 1232: CEF

figure;
subplot(3,3,1);
scatter(record_keffscale(550,:),record_obj(1,:));
title('ATPSm');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,2);
scatter(record_keffscale(554,:),record_obj(1,:));
title('cytochrome c oxidase Complex IV');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,3);
scatter(record_keffscale(560,:),record_obj(1,:));
title('ubiquinone oxidoreductase Complex I');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,4);
scatter(record_keffscale(1216,:),record_obj(1,:));
title('PSII');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,5);
scatter(record_keffscale(1217,:),record_obj(1,:));
title('electron transport system in PS');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,6);
scatter(record_keffscale(1218,:),record_obj(1,:));
title('PSI');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,7);
scatter(record_keffscale(1219,:),record_obj(1,:));
title('ATPSh');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,8);
scatter(record_keffscale(1221,:),record_obj(1,:));
title('chl specific proteins');
set(gca,'YScale','log');
yline(1738);
subplot(3,3,9);
scatter(record_keffscale(1232,:),record_obj(1,:));
title('CEF');
set(gca,'YScale','log');
yline(1738);

% Collect all correlation coef between keffScale and obj
keffCorr = zeros(length(find(variedKeff)),1);

idx = 1;
for i = 1:length(variedKeff)
    if ~variedKeff(i)
        continue;
    else
%         if any([25,43,90,137]==idx)
        if any([20,56,70,119]==idx)
            disp(fullCplx{i});
        end
        
        keffCorr(idx,1) = corr(record_keffscale(i,:)',record_obj(1,:)');
        idx = idx + 1;
    end
end
clear idx i;

% Only larger onces are (corr >= 0.1)
%   enzyme 351: x(501)
%   enzyme 550: x(729)x(726)x(724)x(728)x(711)x(731)x(723)x(712)x(714)x(732)x(717)x(716)x(725)x(730)x(713)x(718)x(719)x(720)
%   enzyme 871: x(1284)
%   enzyme 1217: x(848)x(850)x(849)x(851)x(857)

% Largest positives
%   enzyme 254: x(369) glutathione-disulfide oxidoreductase
%   enzyme 597: x(928) ornithine decarboxylase
%   enzyme 745: x(1128)x(735) D-lactate dehydrogenase
%   enzyme 1123: x(189) ppp

figure;
subplot(2,2,1);
scatter(record_keffscale(254,:),record_obj(1,:));
title('glutathione-disulfide oxidoreductase');
set(gca,'YScale','log');
yline(1738);
subplot(2,2,2);
scatter(record_keffscale(597,:),record_obj(1,:));
title('ornithine decarboxylase');
set(gca,'YScale','log');
yline(1738);
subplot(2,2,3);
scatter(record_keffscale(745,:),record_obj(1,:));
title('D-lactate dehydrogenase');
set(gca,'YScale','log');
yline(1738);
subplot(2,2,4);
scatter(record_keffscale(1123,:),record_obj(1,:));
title('PPP');
set(gca,'YScale','log');
yline(1738);
%}
%}
% proteinList = [517,1187,1190,1186,1175,1182,473,524,466,480,504,1191,496,498,469,168,304];
rxnList = [235,234,237,257,2409];

x = {};
Y = [];
for i = 1:length(model_cyt.rxns)
    if ((length(find(model_auto.S(:,i)))==1) && (abs(FBAsol_hetero.v(i))>1e-2))
        x{length(x)+1} = model_auto.rxns{i};
        Y(length(Y)+1) = FBAsol_hetero.v(i);
    end
end

figure;
title('Exchange Rxns');
X = categorical(x);
X = reordercats(X,x);
bar(X,Y);
clear x X Y;

