package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
)

// json for workflow <-> lambda communication
type workflowRequestType struct {
	Lang      string `json:"lang,omitempty"`      // language to use for ocr
	Scale     string `json:"scale,omitempty"`     // converted image scale factor
	Bucket    string `json:"bucket,omitempty"`    // s3 bucket for source image
	Key       string `json:"key,omitempty"`       // s3 key for source image
	ParentPid string `json:"parentpid,omitempty"` // pid of metadata parent, if applicable
	Pid       string `json:"pid,omitempty"`       // pid of this master_file image
}

type workflowResponseType struct {
	Text string `json:"text,omitempty"`
}

// json for s3 message -> lambda communication
type s3UserIdentityType struct {
	PrincipalID string `json:"principalId,omitempty"`
}

type s3RequestParametersType struct {
	SourceIPAddress string `json:"sourceIPAddress,omitempty"`
}

type s3ResponseElementsType struct {
	XAmzRequestID string `json:"x-amz-request-id,omitempty"`
	XAmzID2       string `json:"x-amz-id-2,omitempty"`
}

type s3OwnerIdentityType struct {
	PrincipalID string `json:"principalId,omitempty"`
}

type s3BucketType struct {
	Name          string              `json:"name,omitempty"`
	OwnerIdentity s3OwnerIdentityType `json:"ownerIdentity,omitempty"`
	Arn           string              `json:"arn,omitempty"`
}

type s3ObjectType struct {
	Key       string `json:"key,omitempty"`
	Size      int    `json:"size,omitempty"`
	ETag      string `json:"eTag,omitempty"`
	VersionID string `json:"versionId,omitempty"`
}

type s3Type struct {
	Name   string       `json:"name,omitempty"`
	Arn    string       `json:"arn,omitempty"`
	Bucket s3BucketType `json:"bucket,omitempty"`
	Object s3ObjectType `json:"object,omitempty"`
}

type s3RecordType struct {
	EventVersion      string                  `json:"eventVersion,omitempty"`
	EventSource       string                  `json:"eventSource,omitempty"`
	AwsRegion         string                  `json:"awsRegion,omitempty"`
	EventTime         string                  `json:"eventTime,omitempty"`
	EventName         string                  `json:"eventName,omitempty"`
	UserIdentity      s3UserIdentityType      `json:"userIdentity,omitempty"`
	RequestParameters s3RequestParametersType `json:"requestParameters,omitempty"`
	ResponseElements  s3ResponseElementsType  `json:"responseElements,omitempty"`
	S3                s3Type                  `json:"s3,omitempty"`
}

type s3MessageEventType struct {
	Records []s3RecordType `json:"Records,omitempty"`
}

// combined request type that encompasses various ways in which this lambda could be invoked
type lambdaRequestType struct {
	workflowRequestType
	s3MessageEventType
}

// json for logged command history
type commandInfo struct {
	Command   string   `json:"command,omitempty"`
	Arguments []string `json:"arguments,omitempty"`
	Output    string   `json:"output,omitempty"`
	Duration  string   `json:"duration,omitempty"`
}

type commandHistory struct {
	Commands []commandInfo `json:"commands,omitempty"`
}

// ocr config for generic conversions irrespective of request source
type ocrConfig struct {
	remoteResultsPrefix string
	languages           string
	scale               string
	bucket              string
	key                 string
	additionalFormats   []string
}

var sess *session.Session
var cmds *commandHistory
var home string

func downloadImage(bucket, key, localFile string) (int64, error) {
	log.Printf("downloading image: s3://%s/%s => %s", bucket, key, localFile)

	downloader := s3manager.NewDownloader(sess)

	f, fileErr := os.Create(localFile)
	if fileErr != nil {
		return -1, fmt.Errorf("failed to create local file: [%s]", fileErr.Error())
	}
	defer f.Close()

	bytes, dlErr := downloader.Download(f,
		&s3.GetObjectInput{
			Bucket: aws.String(bucket),
			Key:    aws.String(key),
		})

	if dlErr != nil {
		return -1, fmt.Errorf("failed to download s3 file: [%s]", dlErr.Error())
	}

	return bytes, nil
}

func uploadResult(uploader *s3manager.Uploader, bucket, remoteResultsPrefix, resultFile string) error {
	s3File := path.Join(remoteResultsPrefix, resultFile)

	log.Printf("uploading file: %s => s3://%s/%s", resultFile, bucket, s3File)

	f, err := os.Open(resultFile)
	if err != nil {
		return fmt.Errorf("failed to open results file: [%s]", err.Error())
	}
	defer f.Close()

	_, err = uploader.Upload(&s3manager.UploadInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(s3File),
		Body:   f,
	})

	return err
}

func uploadResults(bucket, remoteResultsPrefix string) error {
	log.Print("uploading results")

	uploader := s3manager.NewUploader(sess)

	matches, globErr := filepath.Glob("results.*")

	if globErr != nil {
		return fmt.Errorf("failed to find results file(s): [%s]", globErr.Error())
	}

	for _, resultFile := range matches {
		if err := uploadResult(uploader, bucket, remoteResultsPrefix, resultFile); err != nil {
			return fmt.Errorf("failed to upload result: [%s]", err.Error())
		}
	}

	return nil
}

func runCommand(command string, arguments ...string) (string, error) {
	start := time.Now()

	out, err := exec.Command(command, arguments...).CombinedOutput()

	duration := time.Since(start).Seconds()

	output := string(out)

	cmd := commandInfo{Command: command, Arguments: arguments, Output: output, Duration: fmt.Sprintf("%0.3f", duration)}

	cmds.Commands = append(cmds.Commands, cmd)

	log.Printf("command: [%s]  arguments: [%s]  duration: [%s]", cmd.Command, strings.Join(cmd.Arguments, " "), cmd.Duration)

	return output, err
}

func downloadFile(url, filename string) error {
	log.Printf("downloading file: [%s]", url)

	res, err := http.Get(url)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to download language file: [%s] (%s)", url, res.Status)
	}

	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = io.Copy(f, res.Body)

	return err
}

func checkLanguages(langStr string) error {
	langs := strings.Split(langStr, "+")

	// certain languages depend on other language files, make sure they are pulled in

	langsMap := map[string]string{
		"aze":      "aze_cyrl",
		"aze_cyrl": "aze",
		"uzb":      "uzb_cyrl",
		"uzb_cyrl": "uzb",
	}

	// osd should always be present, if not specified in language list
	langsAll := []string{"osd"}

	for _, l := range langs {
		if l == "" {
			continue
		}

		langsAll = append(langsAll, l)

		langDep := langsMap[l]
		if langDep != "" {
			langsAll = append(langsAll, langDep)
		}
	}

	langType := "fast"
	langBranch := "4.0.0"
	langURLTemplate := "https://github.com/tesseract-ocr/tessdata_%s/raw/%s/%s%s.traineddata"

	for _, l := range langsAll {
		var err error

		// check if language file exists
		langFile := fmt.Sprintf("%s/%s.traineddata", os.Getenv("TESSDATA_PREFIX"), l)
		if _, err = os.Stat(langFile); err == nil {
			continue
		}

		// attempt to download as language file
		langURL := fmt.Sprintf(langURLTemplate, langType, langBranch, "", l)
		if err = downloadFile(langURL, langFile); err == nil {
			continue
		}

		// attempt to download as script file
		scriptURL := fmt.Sprintf(langURLTemplate, langType, langBranch, "script/", l)
		if err = downloadFile(scriptURL, langFile); err == nil {
			continue
		}

		// both downloads failed; give up
		return err
	}

	return nil
}

func convertImage(localSourceImage, localConvertedImage, scale string) error {
	log.Print("converting image...")

	cmd := "magick"
	args := []string{"convert", "-units", "PixelsPerInch", "-type", "Grayscale", "+compress", "+repage", fmt.Sprintf("%s[0]", localSourceImage), "-filter", "Lanczos", "-resize", fmt.Sprintf("%s%%", scale), localConvertedImage}

	if out, err := runCommand(cmd, args...); err != nil {
		return fmt.Errorf("failed to convert source image: [%s] (%s)", err.Error(), out)
	}

	return nil
}

func ocrImage(localConvertedImage, resultsBase, langStr string, outputFormats []string) error {
	log.Print("ocring image...")

	cmd := "tesseract"
	args := []string{localConvertedImage, resultsBase, "--psm", "1", "-l", langStr}
	args = append(args, outputFormats...)

	if out, err := runCommand(cmd, args...); err != nil {
		return fmt.Errorf("failed to ocr converted image: [%s] (%s)", err.Error(), out)
	}

	return nil
}

func getLibraryVersions() {
	var files []string

	if matches, err := filepath.Glob(fmt.Sprintf("%s/bin/*", home)); err == nil {
		files = append(files, matches...)
	}

	if matches, err := filepath.Glob(fmt.Sprintf("%s/lib/*", home)); err == nil {
		files = append(files, matches...)
	}

	runCommand("ldd", files...)
}

func getSoftwareVersions() {
	runCommand("magick", "--version")
	runCommand("tesseract", "--version")

	getLibraryVersions()
}

func saveCommandHistory(resultsBase string) {
	cmdsText, jsonErr := json.Marshal(cmds)
	if jsonErr != nil {
		return
	}

	cmdsFile := fmt.Sprintf("%s.log", resultsBase)

	if err := ioutil.WriteFile(cmdsFile, cmdsText, 0644); err != nil {
		return
	}
}

func handleGenericOcrRequest(ocr ocrConfig) (string, error) {
	// set file/path variables

	cmds = &commandHistory{}

	localWorkDir := "/tmp/ocr-lambda"

	// files matching results* are uploaded to s3 at the end of the process
	resultsBase := "results"
	localResultsTxt := fmt.Sprintf("%s.txt", resultsBase)
	localSourceImage := fmt.Sprintf("source-%s", path.Base(ocr.key))
	localConvertedImage := "source-converted.tif"

	outputFormats := []string{"txt"}
	outputFormats = append(outputFormats, ocr.additionalFormats...)

	// set default language if none specified
	langStr := ocr.languages
	if langStr == "" {
		langStr = "eng"
	}

	// create and change to temporary working directory

	if err := os.MkdirAll(localWorkDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create work dir: [%s]", err.Error())
	}

	defer func() {
		// upload whatever results/logs we have, and clean up
		saveCommandHistory(resultsBase)
		uploadResults(ocr.bucket, ocr.remoteResultsPrefix)
		os.Chdir("/")
		os.RemoveAll(localWorkDir)
	}()

	if err := os.Chdir(localWorkDir); err != nil {
		return "", fmt.Errorf("failed to change to work dir: [%s]", err.Error())
	}

	// download image from s3

	_, dlErr := downloadImage(ocr.bucket, ocr.key, localSourceImage)
	if dlErr != nil {
		return "", dlErr
	}

	// log versions of software we are using

	getSoftwareVersions()

	// ensure we have all languages/scripts needed, downloading if necessary

	runCommand("find", os.Getenv("TESSDATA_PREFIX"))
	runCommand("ls", "-laFR", os.Getenv("TESSDATA_PREFIX"))
	if err := checkLanguages(langStr); err != nil {
		return "", err
	}
	runCommand("find", os.Getenv("TESSDATA_PREFIX"))
	runCommand("ls", "-laFR", os.Getenv("TESSDATA_PREFIX"))

	// run magick

	if err := convertImage(localSourceImage, localConvertedImage, ocr.scale); err != nil {
		return "", err
	}

	// run tesseract

	if err := ocrImage(localConvertedImage, resultsBase, langStr, outputFormats); err != nil {
		return "", err
	}

	// read ocr text results

	resultsText, readErr := ioutil.ReadFile(localResultsTxt)
	if readErr != nil {
		return "", fmt.Errorf("failed to read ocr results file: [%s]", readErr.Error())
	}

	// send response

	res := workflowResponseType{}

	res.Text = string(resultsText)

	output, jsonErr := json.Marshal(res)
	if jsonErr != nil {
		return "", fmt.Errorf("failed to serialize output: [%s]", jsonErr.Error())
	}

	return string(output), nil
}

func handleWorkflowOcrRequest(req lambdaRequestType) (string, error) {
	log.Print("handling workflow ocr request")

	ocr := &ocrConfig{}

	// set values from request json

	ocr.bucket = req.Bucket
	ocr.key = req.Key
	ocr.languages = req.Lang
	ocr.scale = req.Scale
	ocr.additionalFormats = []string{"hocr"}

	// build s3 results path

	remoteSubDir := req.Pid
	if req.Pid != req.ParentPid {
		remoteSubDir = path.Join(req.ParentPid, req.Pid)
	}

	ocr.remoteResultsPrefix = path.Join("results", remoteSubDir, req.Scale)

	return handleGenericOcrRequest(*ocr)
}

func handleStandaloneOcrRequest(req lambdaRequestType) (string, error) {
	log.Print("handling standalone ocr request")

	ocr := &ocrConfig{}

	// set values from request json

	ocr.bucket = req.Records[0].S3.Bucket.Name
	ocr.key = req.Records[0].S3.Object.Key
	ocr.languages = ""
	ocr.scale = "100"
	ocr.additionalFormats = []string{"hocr", "pdf"}

	// build s3 results path

	strippedPath := strings.Replace(ocr.key, "standalone/requests/", "", -1)

	ocr.remoteResultsPrefix = path.Join("standalone", "results", strippedPath)

	log.Printf("key: [%s] => [%s] => [%s] => [%s]", ocr.key, path.Dir(ocr.key), strippedPath, ocr.remoteResultsPrefix)

	return handleGenericOcrRequest(*ocr)
}

func handleOcrRequest(ctx context.Context, req lambdaRequestType) (string, error) {
	if req.Pid != "" {
		return handleWorkflowOcrRequest(req)
	}

	if len(req.Records) > 0 {
		return handleStandaloneOcrRequest(req)
	}

	return "", errors.New("unhandled request type")
}

func init() {
	// initialize aws session

	sess = session.Must(session.NewSession())

	// set needed environment variables

	home = os.Getenv("LAMBDA_TASK_ROOT")
	tessdataLocal := "/tmp/tessdata"

	os.Setenv("LD_LIBRARY_PATH", fmt.Sprintf("%s/lib:%s", home, os.Getenv("LD_LIBRARY_PATH")))
	os.Setenv("PATH", fmt.Sprintf("%s/bin:%s", home, os.Getenv("PATH")))
	os.Setenv("TESSDATA_PREFIX", tessdataLocal)

	// copy payload language files to writeable directory (more may be downloaded later)

	tessdataLambda := fmt.Sprintf("%s/share/tessdata", home)

	os.RemoveAll(tessdataLocal)
	exec.Command("cp", "-R", "-p", tessdataLambda, tessdataLocal).Run()
}

func main() {
	lambda.Start(handleOcrRequest)
}
