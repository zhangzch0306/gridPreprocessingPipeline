% gridProcessData(dateDir,varargin) 
%
% This function takes as input the path to the directory (usu DataDir/mouse/date/) 
% of a grid acquisition session,as well asthe path to a template of a cropped 
% .tif file (one that you manually did using ImageJ). It runs the full
% processing pipeline on this directory. 
%
% Required input:
% 1. the path to the directory as a string (e.g., 'D:\MidGridG6-3\191211\')
%
% Optional input:
% 'templateTif' -- the path to a template of a cropped .tif file 
% (e.g., one that you manually did using ImageJ or one from another 
% recording day). This is NECESSARY if you need to crop any of the
% images/movies. Note: you'll get the best results if the template you feed
% is in approximately the same orientation. In cases where the orientation 
% is really different (mirrored, 90deg rotated, etc), this algorithm may
% not work, and you will likely need to crop by hand.
%
% 'motAllow' -- the percent (of total pixels) of motion allowance (default
%   is .1, i.e., 10%... so if your movie frames are 500x500, it would allow
%   x- and y- motion of 50 pixels)
%
% some examples (note that you can mix/match optional inputs in whatever
% order)
% grid_processData('/path/to/input/dir')
% grid_processData('/path/to/input/dir','templateTif','/path/to/crop/template.tif')
% grid_processData('/path/to/input/dir','motAllow',.1,'templateTif','/path/to/crop/template.tif')
% grid_processData('/path/to/input/dir','templateTif','/path/to/crop/template.tif','motAllow',.1)
% grid_processData('/path/to/input/dir','motAllow',.15)
%
% Note: I will use the "mpTiff" to mean long, continuous movie acquisitions 
% broken down into two or more smaller multi-plane .tif files
%
% MAIN PIPELINE: each step will be performed, if needed, depending on the
% files in the directory
%
% 1. split/bin behavioral files according to camera TTLs
% calls function: split_and_bin_grid_behav_files.m
%
% 2. convert .cxd files to multi-plane .tif file(s)
% calls function: cxd2tif.m
%
% 3. group single-plane .tif files into multi-plane .tif file(s)
% calls function: stackIndivTiffFrames.m 
%
% 4. crop .tif files (including mpTiffs)
% calls cropTiffFromTemplate.m & cropMptiffFromTemplate.m
%
% 5. motion correct cropped .tif files (incl mpTiffs files)
% calls function: motion_correct_updated2020.m
%
% 6. do motion-correct BETWEEN mpTiffs
% calls function: mpTiff_motionCorrect.m
%
% for more information, please open the script.
%
% NOTES:
% 1. in the "main pipeline" section of the code, comment out whatever steps 
% you don't want to run
% 2. each of these steps looks in the directory for files to run, and
% then calls functions to perform whatever is needed (crop, motion-correct,
% etc).
% 3. go to the function's section to see how this code determines what
% files to run, what files are done, etc, and what actual function is being 
% called. you may want to edit this and save out your own version for your 
% own data.
% 4. these functions rely on BIO-FORMATS: 
% https://docs.openmicroscopy.org/bio-formats/6.5.1/users/matlab/index.html
%
% Mai-Anh Vu
% updated 1/18/20
% updated 8/2/2020
% updated 9/7/2020: way more commenting, new crop functions, new cxd 
% conversion, use motion_correct_updated2020


%%%%%%%%%%%%%%%%%%%%%
%%% MAIN PIPELINE %%%
%%%%%%%%%%%%%%%%%%%%%
function grid_processData_Alice(dateDir,varargin)

    % turn off some warnings
    warning('off','imageio:tiffmexutils:libtiffWarning')
    warning('off','imageio:tiffmexutils:libtiffErrorAsWarning')
    warning('off','imageio:tifftagsread:expectedTagDataFormatMultiple')
    warning('off', 'MATLAB:imagesci:tiffmexutils:libtiffErrorAsWarning')
    warning('off', 'imagesci:tiffmexutils:libtiffErrorAsWarning')
    warning('off','MATLAB:polyshape:repairedBySimplify')

    %%%  parse inputs %%%
    ip = inputParser;
    ip.addParameter('templateTif','');
    ip.addParameter('motAllow',.1);
    ip.parse(varargin{:});
    for j=fields(ip.Results)'
        eval([j{1} '=ip.Results.' j{1} ';']);
    end
    
    %%% check for bio-formats %%%
    if isempty(which('bfopen'))
        disp('Bio-Formats is not in the path.')
        disp('please make sure Bio-Formats is installed.')
        return
    end
    
    % 1. split and bin behavioral files according to TTLs sent by camera(s)
    % calls function: split_and_bin_grid_behav_files.m
    internal_splitBinBehavFiles(dateDir);   
    
    % 2. look for .cxd files and see if they need to be converted to .tifs
    % if a templateTif has been provided, it will crop in this step as well
    % calls function: cxd2tif.m
    %internal_convertCxd(dateDir,templateTif);

    % Inserted_Lily
    % Look for 405470.tif and see if they need to be split by LED, calls
    % function split_frames_by_LED.m
    internal_splitByLED(dateDir);

    % 3. look for folders (starting with "Image") of single-frame tif files
    % to group into mp-tifs 
    % calls function: stackIndivTiffFrames.m
%    internal_groupTiffSlices(dateDir);
    
    % 4. look for .tif files and mp-tif files (mp-tif files are in folders 
    % starting with "mpImage") to crop     
    % calls cropTiffFromTemplate.m & cropMptiffFromTemplate.m
%    internal_cropTiffs(dateDir,templateTif);   
    
    % 5. look for CROPPED .tif files and mp-tif files (mp-tif files are in 
    % folders starting with "mpImage") to motion-correct  
    % calls function: motion_correct_updated2020.m
    internal_motionCorrTiffs(dateDir,motAllow);
    
    % 6. look for motion-corrected mp-tif files (motion-corrected mp-tif files 
    % are in the same folders as the cropped ones)to do motion-correction 
    % BETWEEN files
    % calls function: mpTiff_motionCorrect.m
%    internal_motCorrBetwTiffs(dateDir);

    % 7. fitGridROIs using the roi template in the folder
%    internal_fitGridROIs(dateDir);
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% SPLIT & BIN BEHAV FILES %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_splitBinBehavFiles(dateDir)
    % let's first get all the files in the directory
    matFiles = dir(dateDir);
    matFiles = {matFiles.name}';
    % look for .mat files that start with the mouse's name -- this assumes
    % that the folder containing this date directory is the mouse's name
    % for example: /path/to/data/MOUSE/200901
    mouseName = strsplit(dateDir,filesep);
    mouseName = mouseName(~cellfun(@isempty,mouseName));
    mouseName = mouseName{end-1};
    % look for files that start with the mouse's name and end with .mat
    matFiles = matFiles(startsWith(matFiles,mouseName) & endsWith(matFiles,'.mat'));
    % excluded files that have the word "movie" in them, as these are
    % already split/binned
    rawMatFiles = matFiles(~endsWith(matFiles,'ROIs.mat') & ~contains(matFiles,'movie'));
    % get a list of the processed files
    processedMatFiles = setdiff(matFiles,rawMatFiles);
    % loop over the unprocessed behavioral files
    for f = 1:numel(rawMatFiles)
        matFile = rawMatFiles{f};
        file = fullfile(dateDir,matFile);
        % let's check to make sure we haven't done it already:
        % see if there are any processedMatFiles at all, and if so, look to
        % see if that none match our filename (everything before the .mat)
        if isempty(processedMatFiles) | ~contains(processedMatFiles,matFile(1:end-4))
            disp(['   splitting and binning: ' file])
            try
                virmenStartTTL = 3;
                [~,retry] = split_and_bin_grid_behav_files(file,'virmenStartTTL',virmenStartTTL);
                while sum(retry) > 0 && virmenStartTTL <= 15
                    virmenStartTTL = virmenStartTTL + 1;
                    disp(['       ...trying virmenStartTTL = ' num2str(virmenStartTTL)]);
                    [~,retry] = split_and_bin_grid_behav_files(file,'virmenStartTTL',virmenStartTTL);
                end
                if virmenStartTTL == 20 && retry == 1
                    disp('       *** ERROR: could not find good virmen-behav match')
                    disp('       i.e.: could not find a good value for virmenStartTTL')
                end
            catch exception
                disp('       *** ERROR SPLITTING/BINNING BEHAV ***')
            end
        else
            disp(['   already split/bin: '  file])
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% CONVERT .cxd TO .tif %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_convertCxd(dateDir,templateTif)
    % get a list of files in the directory
    potentialImageFiles = dir(dateDir);
    potentialImageFileNames = {potentialImageFiles.name}';
    % cxd files are the ones that end with .cxd
    cxdFiles = potentialImageFileNames(endsWith(potentialImageFileNames,'.cxd'));
    tifFiles = potentialImageFileNames(endsWith(potentialImageFileNames,'.tif'));
    % loop over cxdFiles
    for c = 1:numel(cxdFiles)
        cxdFile = cxdFiles{c};
        cxdFilepath = fullfile(dateDir,cxdFile);
        % let's look if there's a .tif file or an mpImage folder that would
        % correspond with this
        tifFileCheck = tifFiles(startsWith(tifFiles,cxdFile(1:end-4)) & endsWith(tifFiles,'.tif'));
        mpTifFileCheck = potentialImageFileNames(startsWith(potentialImageFileNames,['mpImage_' cxdFile(1:end-4)]));
        if isempty(tifFileCheck) && isempty(mpTifFileCheck)
            disp(['   ' cxdFile ' converting to .tif'])
            try
                % if there's a template provided, let's crop it at the same
                % time to save space
                if ~isempty(templateTif)
                    outputTifs = cxd2tif(cxdFilepath,'crop',1,'templateTifFilepath',templateTif); 
                else % if template is empty, don't crop it, but save as _crop
                    outputTifs = cxd2tif(cxdFilepath,'crop',1,'templateTifFilepath','','maxSizeGB',20); 
                end
                % if there's more than one, we'll consider it an mptiff and
                % put them in a folder together
                if numel(outputTifs)>1 
                    if ~isempty(templateTif) % if it's cropped
                        mkdir(mpTifDirCrop)
                    else % if it's not cropped
                        mkdir(mpTifDir)
                    end
                    for op = 1:numel(outputTifs)
                        % isolate the filename to move
                        filename = strsplit(outputTifs{op},filesep);
                        filename = filename(~cellfun(@isempty,filename));
                        filename = filename{end}; 
                        % now move it
                        if ~isempty(templateTif) % if it's cropped
                            movefile(outputTifs{op},fullfile(mpTifDirCrop,filename));
                        else % if it's not cropped
                            movefile(outputTifs{op},fullfile(mpTifDir,filename));
                        end
                    end
                end
            catch exception
                disp('       *** ERROR WITH CXD CONVERSION ***')
            end
        else
            disp(['   ' cxdFile ' already converted'])
        end               
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% GROUP SINGLE .tif SLICES INTO MULTI-PLANE .tif FILES %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_groupTiffSlices(dateDir)
    % look for directories that start with "Image" - these have the single-plane tifs in them
    potentialImageFiles = dir(dateDir);
    potentialImageFileNames = {potentialImageFiles.name}';
    potentialImageFileIsdir = {potentialImageFiles.isdir}';
    stackTiffDirs = potentialImageFileNames(startsWith(potentialImageFileNames,'Image') & cell2mat(potentialImageFileIsdir)==1);   
    % loop over these folders 
    for s = 1:numel(stackTiffDirs)
        stackTiffDirName = stackTiffDirs{s};
        stackTiffDir = fullfile(dateDir, stackTiffDirName);
        % once we group them, we'll put the new ones in a folder that's the same but starts with 'mp'
        % check for this folder
        mpConvDir = fullfile(dateDir,['mp' stackTiffDirs{s}]);
        % and check for files will start with the same name as the
        % directory
        groupedTifs = potentialImageFileNames(startsWith(potentialImageFileNames,stackTiffDirName)&cell2mat(potentialImageFileIsdir)==0);        
        % check if we've already made into mpTiffs
        if exist(mpConvDir,'dir') || ~isempty(groupedTifs)
            disp(['   ' stackTiffDirs{s} ': indiv tiffs already grouped into mpTiffs (stacks)'])
        else
            disp(['   ' stackTiffDirs{s} ':grouping indiv into mpTiffs (stacks)'])
            try
                outputMpTiffDir = stackIndivTiffFrames(stackTiffDir,1); % set this to 1 if your .tif filenames have leading zeros
                % let's just check whether we have just one file
                newMpTiffs = dir(outputMpTiffDir);
                newMpTiffs = {newMpTiffs.name}';
                newMpTiffs = newMpTiffs(endsWith(newMpTiffs,'.tif'));
                % if it's just one file, move it out of that directory into 
                % the main directory and then delete the empty directory
                if numel(newMpTiffs)==1
                    movefile(fullfile(outputMpTiffDir,newMpTiffs{1}),fullfile(dateDir,newMpTiffs{1}));
                    delete(outputMpTiffDir)
                end
            catch exception
                disp('       *** ERROR WITH TIF STACKING ***')
            end
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% CROP TIF FILES (INCL MPTIFF) %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_cropTiffs(dateDir,templateTif)
    % let's just get a list of files and directories in here
    potentialImageFiles = dir(dateDir);
    potentialImageFileNames = {potentialImageFiles.name}';
    potentialImageFileIsdir = {potentialImageFiles.isdir}';
    % let's first look for standalone uncropped tif files
    tifFiles = potentialImageFileNames(endsWith(potentialImageFileNames,'.tif'));
    % ignore the ones that end with crop.tif (these are cropped)
    tifFiles = tifFiles(~contains(tifFiles,'_crop')); 
    % loop over these files, and if they're not cropped yet, crop them
    for f = 1:numel(tifFiles)
        tifFile = tifFiles{f};
        croppedFile = [tifFile(1:end-4) '_crop.tif'];
        if ~exist(fullfile(dateDir,croppedFile),'file')
            disp(['   ' tifFile ': cropping'])
            try
                cropTiffFromTemplate(fullfile(dateDir,tifFile),templateTif);
            catch exception
                disp('       *** ERROR WITH CROPPING TIF ***')
            end
        else
            disp(['   ' tifFile ': tif file already cropped'])             
        end
    end
    % now let's look for mpTiff directories and see if there are any we need to crop
    mpTiffDirs = potentialImageFileNames(startsWith(potentialImageFileNames,'mpImage') & cell2mat(potentialImageFileIsdir)==1);
    mpTiffDirs = mpTiffDirs(~contains(mpTiffDirs,'_crop')); % just list the uncropped ones
    % loop over potential mpTiff directories that need to be cropped
    for mp = 1:numel(mpTiffDirs)
        % the input directory
        mpTiffDir = fullfile(dateDir, mpTiffDirs{mp});
        mpTiffDirCrop = fullfile(dateDir, [mpTiffDirs{mp} '_crop']);
        % the output directory
        % if the output directory doesn't exist, we should crop 
        % assumption: if the output directory exists, we'll assume it's done so won't redo it
        if ~exist(mpTiffDirCrop,'dir') 
            try
                disp(['   ' mpTiffDir ': cropping'])
                cropMptiffFromTemplate(mpTiffDir,templateTif,'outputDir',mpTiffDirCrop);
            catch exception
                disp('       *** ERROR WITH CROPPING MPTIFF ***')
            end
        else
            disp(['   ' mpTiffDir ': mptiffs already cropped'])  
        end
    end      
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Split by LED all 405470.tif FILES %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_splitByLED(dateDir)
    % look for .tif files that end in 405470.tif but don't end with MC.tif - 
    % these have been cropped and potentially need to be motion-corrected
    allFiles = dir(dateDir);
    allFiles = {allFiles.name}';
    tifFiles = allFiles(endsWith(allFiles,'405470.tif'));
    
    % look for .mat files that end in movie[?].mat
    % look for .mat files that start with the mouse's name -- this assumes
    % that the folder containing this date directory is the mouse's name
    % for example: /path/to/data/MOUSE/200901
    mouseName = strsplit(dateDir,filesep);
    mouseName = mouseName(~cellfun(@isempty,mouseName));
    mouseName = mouseName{end-1};
    % look for files that start with the mouse's name and end with .mat
    behavFiles = allFiles(startsWith(allFiles,mouseName) & endsWith(allFiles,pattern("movie" + digitsPattern + ".mat")));
    % loop over the files
    for t = 1:numel(tifFiles)
        tifFile = tifFiles{t};
        file = fullfile(dateDir, tifFile);
        % first check if there is splited tiff
        splitted405 = [file(1:end-4) '_405.tif'];
        splitted470 = [file(1:end-4) '_470.tif'];
        % if there isn't, then we'll go ahead and split tif files
        if ~(exist(splitted405,'file') | exist(splitted470,'file'))
            % find the matching behavior file for this tif file.
            disp(['   ' tifFile ': finding matching behavior movie...'])
            pat = tifFile(1:end-11);
            for b = behavFiles'
                if contains(b{1},pat)
                    behavFile = b{1};
                    disp(['   ' tifFile ': behavior movie found -- ' behavFile])
                    %get full path for behav file
                    behavFile = fullfile(dateDir, behavFile);
                end
            end                     
            disp(['   ' tifFile ': splitting frames by LED...'])
            try
                split_frames_by_LED(behavFile,'tifFilepath',file);
            catch exception
                disp('       *** ERROR WITH SPLITTING FRAMES ***')
            end
        else
            disp(['   ' tifFile ': split frames by LED is already done.'])
        end        
    end
    
end


% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%% manually fitting ROI files %%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_fitGridROIs(dateDir)
    % look for all the files ended with _ROIs.mat, if this ROI file have a
    % very small file size, then this file is a template ROI file. Apply
    % fitGridROIs function to this MC file.

allFiles = dir(dateDir);
fileNames = {allFiles.name}';
fileSize = {allFiles.bytes}';
% size selecting criteria
sizeCriteria=(cell2mat(fileSize)<=10000000);
roiFiles = allFiles(endsWith(fileNames,'_ROIs.mat') & sizeCriteria);

if ~isempty(roiFiles)
    display('Small ROI templates are detected.')
    for i=1:size(roiFiles,1)
        file=roiFiles(i,:);
        tempRoiFilePath=[dateDir,filesep,file.name];
        targetMcFilePath=[tempRoiFilePath(1:end-9),'.tif'];
        display(['Fitting ROI for',targetMcFilePath]);
        try
            fitGridROIs(targetMcFilePath,tempRoiFilePath);
        catch exception
            disp(' *** Error with fitting ROIs *** ')
        end
        display('Fitting is done');
    end
end

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% MOTION CORRECT ALL .tif FILES %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_motionCorrTiffs(dateDir,motAllow)
    % look for .tif files that end in crop.tif but don't end with MC.tif - 
    % these have been cropped and potentially need to be motion-corrected
    tifFiles = dir(dateDir);
    tifFiles = {tifFiles.name}';
    tifFiles = tifFiles(endsWith(tifFiles,'_405.tif')|endsWith(tifFiles,'_470.tif')&~endsWith(tifFiles,'MC.tif'));
    % loop over the files
    for t = 1:numel(tifFiles)
        tifFile = tifFiles{t};
        file = fullfile(dateDir, tifFile);
        % first check if there is a motion corrected one
        mcFile = [file(1:end-4) '_MC.tif'];
        % if there isn't, then we'll go ahead and motion-correct
        if ~exist(mcFile,'file')
            disp(['   ' tifFile ': motion-correcting...'])
            tifInfo = imfinfo(file);
            tifHeight = tifInfo.Height;
            tifWidth = tifInfo.Width;
            try
                motion_correct_updated2020(file,'outfile',mcFile,'crop_points',[round(tifWidth*.15) round(tifHeight*.15) round(tifWidth*.85) round(tifHeight*.85)],'maxshift_x',round(tifWidth*motAllow),'maxshift_y',round(tifHeight*motAllow));
            catch exception
                disp('       *** ERROR WITH MOTION CORRECTION ***')
            end
        else
            disp(['   ' tifFile ': motion correction already done.'])
        end        
    end
    
    % also look for mpTiff dirs with '_crop' on the end
    potentialImageFiles = dir(dateDir);
    potentialImageFileNames = {potentialImageFiles.name}';
    potentialImageFileIsdir = {potentialImageFiles.isdir}';   
    % look for directories that start with "mpImage" and end with "crop"
    croppedMpTiffDirs = potentialImageFileNames(startsWith(potentialImageFileNames,'mpImage') & endsWith(potentialImageFileNames,'_crop') & cell2mat(potentialImageFileIsdir)==1);
    % loop over those cropped mp tiff directories
    for mp = 1:numel(croppedMpTiffDirs)
        croppedMpTiffDir = fullfile(dateDir,croppedMpTiffDirs{mp});
        % get a list of files inside the mptiff directory
        tifFiles = dir(croppedMpTiffDir);
        tifFiles = {tifFiles.name}';
        % look for .tif fiels that haven't been motion-corrected (don't end
        % in "_MC"
        tifFiles = tifFiles(endsWith(tifFiles,'.tif') & ~endsWith(tifFiles,'_MC.tif'));
        % loop over the files
        for f = 1:numel(tifFiles)
            tifFile = tifFiles{f};
            file = fullfile(croppedMpTiffDir, tifFile);
            % if the file doesn't already have a matching _MC.tif file,
            % motion-correct it
            mcFile = [file(1:end-4) '_MC.tif'];           
            if ~exist(mcFile,'file')
                disp(['   ' croppedMpTiffDirs{mp} ': ' tifFile ': motion-correcting...'])
                tifInfo = imfinfo(file);
                tifHeight = tifInfo.Height;
                tifWidth = tifInfo.Width;
                try% we're allowing "motAllow" % motion, and using a 15% & 85% crop to estimate the motion-correction
                    motion_correct_updated2020(file,'outfile',mcFile,'crop_points',[round(tifWidth*.15) round(tifHeight*.15) round(tifWidth*.85) round(tifHeight*.85)],'maxshift_x',round(tifWidth*motAllow),'maxshift_y',round(tifHeight*motAllow));
                catch exception
                    disp('       *** ERROR WITH MOTION CORRECTION ***')
                end                    
            else
                disp(['   ' croppedMpTiffDirs{mp} ': ' tifFile ': motion correction already done.'])
            end              
        end
    end     
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% 2nd MOTION-CORRECTION BETWEEN mpTiffs (to get them into same space) %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function internal_motCorrBetwTiffs(dateDir)
    % look for mpTiff dirs with '_crop' on the end
    potentialImageFiles = dir(dateDir);
    potentialImageFileNames = {potentialImageFiles.name}';
    potentialImageFileIsdir = {potentialImageFiles.isdir}';      
    croppedMpTiffDirs = potentialImageFileNames(startsWith(potentialImageFileNames,'mpImage') & endsWith(potentialImageFileNames,'_crop') & cell2mat(potentialImageFileIsdir)==1);
    % loop over the mpTiff "_crop" dirs
    for mp = 1:numel(croppedMpTiffDirs)
        croppedMpTiffDir = fullfile(dateDir, croppedMpTiffDirs{mp});
        % get a list of files within
        tifFiles = dir(croppedMpTiffDir);
        tifFiles = {tifFiles.name}';
        % get a list of raw .tif files (don't end with "_MC.tif")
        rawTifFiles = tifFiles(endsWith(tifFiles,'.tif') & ~endsWith(tifFiles,'_MC.tif'));
        % and also get a list of motion-correct ones (end with "_MC.tif")
        mcTifFiles =  tifFiles(endsWith(tifFiles,'.tif') & endsWith(tifFiles,'_MC.tif'));
        % make sure those numbers match, i.e., that all the tifs jave been 
        % individually motion-corrected   
        % either check that there are no raw tif files, or that all the
        % ones that are there have been motion-corrected
        if isempty(rawTifFiles) || numel(rawTifFiles)==numel(mcTifFiles) 
            % make an output directory if necessary
            outputMCdir = fullfile(dateDir,[croppedMpTiffDirs{mp} '_MCMC']);
            if ~exist(outputMCdir,'dir')
                mkdir(outputMCdir)
            end
            % look to see if we already have any twice-motion-corrected
            % files
            MCMCcount = dir(outputMCdir);
            MCMCcount = {MCMCcount.name}';
            MCMCcount = sum(endsWith(MCMCcount,'_MC_MC.tif')); 
            % if the number of twice-motion-corrected doesn't match the
            % number of files, go ahead and motion-correct between them
            if MCMCcount<numel(mcTifFiles)
                disp(['   ' croppedMpTiffDirs{mp} ': motion-correcting between movies.'])
                % make the cell array list of movie files
                mpTiffListCellArray = cell(size(mcTifFiles));
                % loop over those files
                for f = 1:numel(mcTifFiles)
                    mpTiffListCellArray{f} = fullfile(croppedMpTiffDir, mcTifFiles{f});
                end
                % now motion-correct them with respect to each other
                try
                    mpTiff_motionCorrect(mpTiffListCellArray,outputMCdir)
                catch exception
                    disp('       *** ERROR WITH MPTIFF 2nd MOTION CORR ***')
                end

            else
                disp(['   ' croppedMpTiffDirs{mp} ': between-movie motion correction already done.'])
            end
        else
            disp(['   ' croppedMpTiffDirs{mp} ': the raw files are not all motion-corrected.'])
        end
    end      
end

